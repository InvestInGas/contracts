// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {
    ReentrancyGuard
} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {GasStructs} from "./library/GasStructs.sol";
import {GasConstants} from "./library/Constants.sol";
import {GasErrors} from "./library/Errors.sol";
import {GasMath} from "./library/GasMath.sol";
import {SignatureUtils} from "./library/SignatureUtils.sol";
import {LiFiHandler} from "./handlers/LiFiHandler.sol";
import {SafeCast} from "@openzeppelin/contracts/utils/math/SafeCast.sol";

/**
 * @title InvestInGasFutures
 * @notice Core contract for gas credit purchase, redemption, and management on Arc L1
 * @dev Uses relayer pattern - prices come from Sui oracle via trusted relayer
 */
contract InvestInGasFutures is Ownable, Pausable, ReentrancyGuard, LiFiHandler {
    using GasStructs for *;
    using SafeCast for uint256;

    // Fees
    address public feeRecipient;
    uint256 public constant PROTOCOL_FEE_BPS = 50;
    uint256 public constant EXPIRY_REFUND_FEE_BPS = 200;

    // Relayer
    address public relayerAddress;

    // User credits
    mapping(address => GasStructs.GasCredit[]) public userCredits;

    // Supported chains
    mapping(string => bool) public supportedChains;
    mapping(string => GasStructs.ChainGasPrice) public chainGasPrices;

    event CreditsPurchased(
        address indexed user,
        uint256 indexed creditId,
        uint256 usdcAmount,
        uint256 lockedPriceGwei,
        uint256 gasUnits,
        string targetChain,
        uint256 expiry
    );

    event CreditsRedeemed(
        address indexed user,
        uint256 indexed creditId,
        uint256 gasUnitsUsed,
        uint256 savedAmountUsdc,
        string targetChain,
        uint256 marketPriceGwei,
        bool cashSettlement
    );

    event CreditsTransferred(
        address indexed from,
        address indexed to,
        uint256 indexed creditId,
        uint256 gasUnits
    );

    event CreditExpiredRefunded(
        address indexed user,
        uint256 indexed creditId,
        uint256 refundAmount,
        uint256 feeAmount
    );

    event ChainSupportUpdated(string chain, bool supported);

    event RelayerAddressUpdated(
        address indexed oldRelayer,
        address indexed newRelayer
    );

    modifier onlyRelayer() {
        _checkRelayer();
        _;
    }

    function _checkRelayer() internal view {
        if (msg.sender != relayerAddress) revert GasErrors.NotRelayer();
    }

    constructor(
        address _usdc,
        address _relayer,
        address _feeRecipient
    ) Ownable(msg.sender) LiFiHandler(_usdc) {
        USDC = IERC20(_usdc);
        relayerAddress = _relayer;
        feeRecipient = _feeRecipient;
        supportedChains["ethereum"] = true;
        supportedChains["base"] = true;
        supportedChains["arbitrum"] = true;
        supportedChains["polygon"] = true;
        supportedChains["optimism"] = true;
    }

    /**
     * Purchase credits via relayer
     * Relayer submits on behalf of user, price comes from our Sui oracle
     */
    function purchaseCredits(
        address user,
        uint256 usdcAmount,
        string calldata targetChain,
        uint256 expiryDays,
        uint256 priceGwei,
        uint256 ethPriceUsd,
        uint256 timestamp,
        bytes calldata userSignature
    ) external nonReentrant whenNotPaused onlyRelayer returns (uint256) {
        if (block.timestamp - timestamp > 5 minutes)
            revert GasErrors.IntentExpired();

        bytes32 messageHash = SignatureUtils.hashPurchaseMessage(
            user,
            usdcAmount,
            targetChain,
            expiryDays,
            priceGwei,
            ethPriceUsd,
            timestamp
        );
        bytes32 ethSignedHash = SignatureUtils.toEthSignedMessageHash(
            messageHash
        );
        address signer = SignatureUtils.recoverSigner(
            ethSignedHash,
            userSignature
        );
        if (signer != user) revert GasErrors.InvalidUserSignature();

        if (usdcAmount < GasConstants.MIN_PURCHASE)
            revert GasErrors.BelowMinimumPurchase();
        if (usdcAmount > GasConstants.MAX_PURCHASE)
            revert GasErrors.AboveMaximumPurchase();
        if (expiryDays < GasConstants.MIN_EXPIRY / 1 days)
            revert GasErrors.ExpiryTooShort();
        if (expiryDays > GasConstants.MAX_EXPIRY / 1 days)
            revert GasErrors.ExpiryTooLong();
        if (!supportedChains[targetChain]) revert GasErrors.ChainNotSupported();
        if (priceGwei == 0) revert GasErrors.InvalidPrice();

        (uint256 netAmount, uint256 fee, uint256 gasUnits) = GasMath
            .calculateGasUnits(
                usdcAmount,
                PROTOCOL_FEE_BPS,
                priceGwei,
                ethPriceUsd
            );

        bool success = USDC.transferFrom(user, address(this), usdcAmount);
        if (!success) revert GasErrors.TransferFailed();

        if (fee > 0) {
            bool feeSuccess = USDC.transfer(feeRecipient, fee);
            if (!feeSuccess) revert GasErrors.TransferFailed();
        }

        uint256 creditId = userCredits[user].length;
        uint40 expiry = uint40(block.timestamp + (expiryDays * 1 days));

        userCredits[user].push(
            GasStructs.GasCredit({
                lockedPriceGwei: priceGwei.toUint96(),
                gasUnits: gasUnits.toUint128(),
                remainingGasUnits: gasUnits.toUint128(),
                expiry: expiry,
                targetChain: targetChain,
                isActive: true,
                purchaseTimestamp: uint40(block.timestamp),
                usdcPaid: netAmount.toUint128()
            })
        );

        emit CreditsPurchased(
            user,
            creditId,
            usdcAmount,
            priceGwei,
            gasUnits,
            targetChain,
            expiry
        );

        return creditId;
    }

    /**
     * Redeem credits via relayer
     * Relayer submits on behalf of user, prices come from external sources
     */
    function redeemCredits(
        address user,
        uint256 creditId,
        uint256 gasUnitsToUse,
        uint256 currentPriceGwei,
        uint256 ethPriceUsd,
        uint256 timestamp,
        bytes calldata userSignature,
        bytes calldata lifiData,
        bool cashSettlement
    ) external nonReentrant whenNotPaused onlyRelayer returns (uint256) {
        if (block.timestamp - timestamp > 5 minutes)
            revert GasErrors.IntentExpired();

        bytes32 lifiDataHash;
        assembly {
            lifiDataHash := keccak256(lifiData.offset, lifiData.length)
        }

        bytes32 messageHash = SignatureUtils.hashRedeemMessage(
            user,
            creditId,
            gasUnitsToUse,
            currentPriceGwei,
            ethPriceUsd,
            timestamp,
            lifiDataHash,
            cashSettlement
        );
        bytes32 ethSignedHash = SignatureUtils.toEthSignedMessageHash(
            messageHash
        );
        address signer = SignatureUtils.recoverSigner(
            ethSignedHash,
            userSignature
        );
        if (signer != user) revert GasErrors.InvalidUserSignature();

        if (creditId >= userCredits[user].length)
            revert GasErrors.InvalidCreditId();

        GasStructs.GasCredit storage credit = userCredits[user][creditId];
        if (!credit.isActive) revert GasErrors.CreditInactive();
        if (block.timestamp >= credit.expiry) revert GasErrors.CreditExpired();
        if (gasUnitsToUse > credit.remainingGasUnits)
            revert GasErrors.InsufficientGasUnits();

        if (currentPriceGwei <= credit.lockedPriceGwei)
            revert GasErrors.NoSavingsAvailable();

        uint256 savedAmount = GasMath.calculateSavings(
            currentPriceGwei,
            credit.lockedPriceGwei,
            gasUnitsToUse,
            ethPriceUsd
        );
        if (USDC.balanceOf(address(this)) < savedAmount)
            revert GasErrors.InsufficientContractBalance();

        credit.remainingGasUnits -= gasUnitsToUse.toUint128();
        if (credit.remainingGasUnits == 0) {
            credit.isActive = false;
        }

        if (cashSettlement) {
            bool success = USDC.transfer(user, savedAmount);
            if (!success) revert GasErrors.TransferFailed();
        } else {
            _executeLifiBridge(savedAmount, lifiData, credit.targetChain);
        }

        emit CreditsRedeemed(
            user,
            creditId,
            gasUnitsToUse,
            savedAmount,
            credit.targetChain,
            currentPriceGwei,
            cashSettlement
        );

        return savedAmount;
    }

    /**
     * Transfer gas credits to another address
     */
    function transferCredits(
        uint256 creditId,
        address to,
        uint256 gasUnitsToTransfer
    ) external nonReentrant whenNotPaused {
        if (creditId >= userCredits[msg.sender].length)
            revert GasErrors.InvalidCreditId();
        if (to == address(0) || to == msg.sender)
            revert GasErrors.InvalidRecipient();

        GasStructs.GasCredit storage credit = userCredits[msg.sender][creditId];
        if (!credit.isActive) revert GasErrors.CreditInactive();
        if (block.timestamp >= credit.expiry) revert GasErrors.CreditExpired();
        if (gasUnitsToTransfer > credit.remainingGasUnits)
            revert GasErrors.InsufficientGasUnits();

        credit.remainingGasUnits -= gasUnitsToTransfer.toUint128();
        if (credit.remainingGasUnits == 0) {
            credit.isActive = false;
        }
        uint256 proportionalUsdc = (uint256(credit.usdcPaid) *
            gasUnitsToTransfer) / credit.gasUnits;

        userCredits[to].push(
            GasStructs.GasCredit({
                lockedPriceGwei: credit.lockedPriceGwei,
                gasUnits: gasUnitsToTransfer.toUint128(),
                remainingGasUnits: gasUnitsToTransfer.toUint128(),
                expiry: credit.expiry,
                targetChain: credit.targetChain,
                isActive: true,
                purchaseTimestamp: uint40(block.timestamp),
                usdcPaid: proportionalUsdc.toUint128()
            })
        );

        emit CreditsTransferred(msg.sender, to, creditId, gasUnitsToTransfer);
    }

    /**
     * Claim refund for an expired credit
     */
    function claimExpiredRefund(
        uint256 creditId
    ) external nonReentrant returns (uint256 refundAmount) {
        if (creditId >= userCredits[msg.sender].length)
            revert GasErrors.InvalidCreditId();

        GasStructs.GasCredit storage credit = userCredits[msg.sender][creditId];

        if (!credit.isActive) revert GasErrors.CreditInactive();
        if (block.timestamp < credit.expiry)
            revert GasErrors.CreditNotExpired();
        credit.isActive = false;

        uint256 fee;
        (refundAmount, fee) = GasMath.calculateRefund(
            credit.usdcPaid,
            credit.remainingGasUnits,
            credit.gasUnits,
            EXPIRY_REFUND_FEE_BPS
        );

        if (USDC.balanceOf(address(this)) < refundAmount)
            revert GasErrors.InsufficientContractBalance();

        if (refundAmount > 0) {
            bool success = USDC.transfer(msg.sender, refundAmount);
            if (!success) revert GasErrors.TransferFailed();
        }

        if (fee > 0) {
            bool feeSuccess = USDC.transfer(feeRecipient, fee);
            if (!feeSuccess) revert GasErrors.TransferFailed();
        }

        emit CreditExpiredRefunded(msg.sender, creditId, refundAmount, fee);
    }

    /**
     * Get all credits for a user
     */
    function getUserCredits(
        address user
    ) external view returns (GasStructs.GasCredit[] memory) {
        return userCredits[user];
    }

    /**
     * Get a specific credit for a user
     */
    function getUserCredit(
        address user,
        uint256 creditId
    ) external view returns (GasStructs.GasCredit memory) {
        require(creditId < userCredits[user].length, "Invalid credit ID");
        return userCredits[user][creditId];
    }

    /**
     * Get the number of credits for a user
     */
    function getUserCreditsCount(address user) external view returns (uint256) {
        return userCredits[user].length;
    }

    /**
     * Get total active gas units for a user across all credits
     */
    function getUserTotalGasUnits(
        address user
    ) external view returns (uint256 totalUnits, uint256 totalValueUsdc) {
        GasStructs.GasCredit[] storage credits = userCredits[user];
        for (uint256 i = 0; i < credits.length; i++) {
            if (credits[i].isActive && block.timestamp < credits[i].expiry) {
                totalUnits += credits[i].remainingGasUnits;
                totalValueUsdc +=
                    (uint256(credits[i].usdcPaid) *
                        credits[i].remainingGasUnits) /
                    credits[i].gasUnits;
            }
        }
    }

    /**
     * Get contract USDC balance available for payouts
     */
    function getAvailableBalance() external view returns (uint256) {
        return USDC.balanceOf(address(this));
    }

    /**
     * @notice Get gas price data for a specific chain
     */
    function getGasPriceData(
        string calldata chain
    ) external view returns (GasStructs.ChainGasPrice memory) {
        return chainGasPrices[chain];
    }

    /**
     * Update the relayer address
     */
    function setRelayerAddress(address _relayer) external onlyOwner {
        address oldRelayer = relayerAddress;
        relayerAddress = _relayer;
        emit RelayerAddressUpdated(oldRelayer, _relayer);
    }

    /**
     * Update the LiFi Diamond address
     */
    function setLifiDiamond(address _lifiDiamond) external onlyOwner {
        _setLifiDiamond(_lifiDiamond);
    }

    /**
     * Update the fee recipient address
     */
    function setFeeRecipient(address _recipient) external onlyOwner {
        feeRecipient = _recipient;
    }

    /**
     * Add or remove chain support
     */
    function setChainSupport(
        string calldata chain,
        bool supported
    ) external onlyOwner {
        supportedChains[chain] = supported;
        emit ChainSupportUpdated(chain, supported);
    }

    /**
     * Pause the contract
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * Emergency withdraw USDC
     */
    function emergencyWithdraw(uint256 amount) external onlyOwner whenPaused {
        bool success = USDC.transfer(owner(), amount);
        if (!success) revert GasErrors.TransferFailed();
    }

    /**
     * Deposit USDC to fund payouts
     */
    function depositLiquidity(uint256 amount) external {
        bool success = USDC.transferFrom(msg.sender, address(this), amount);
        if (!success) revert GasErrors.TransferFailed();
    }
}
