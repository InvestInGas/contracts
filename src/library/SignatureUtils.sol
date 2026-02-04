// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title SignatureUtils
 * @notice Helper library for signature verification
 */
library SignatureUtils {
    function recoverSigner(
        bytes32 ethSignedHash,
        bytes calldata signature
    ) internal pure returns (address) {
        require(signature.length == 65, "Invalid signature length");

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }

        if (v < 27) {
            v += 27;
        }

        return ecrecover(ethSignedHash, v, r, s);
    }

    /**
     * @notice Convert a message hash to an Ethereum signed message hash
     * @dev Uses assembly for gas optimization
     */
    function toEthSignedMessageHash(
        bytes32 messageHash
    ) internal pure returns (bytes32 result) {
        // The prefix is "\x19Ethereum Signed Message:\n32" (28 bytes)
        // Total: 28 + 32 = 60 bytes
        assembly {
            // Get free memory pointer
            let ptr := mload(0x40)
            // Store the prefix
            mstore(ptr, "\x19Ethereum Signed Message:\n32")
            // Store the message hash after the prefix (at offset 28)
            mstore(add(ptr, 28), messageHash)
            // Hash 60 bytes starting from ptr
            result := keccak256(ptr, 60)
        }
    }

    /**
     * @notice Hash purchase message parameters using assembly
     * @dev Optimized to avoid abi.encodePacked memory allocation
     */
    function hashPurchaseMessage(
        address user,
        uint256 usdcAmount,
        string calldata targetChain,
        uint256 expiryDays,
        uint256 priceGwei,
        uint256 ethPriceUsd,
        uint256 ts
    ) internal pure returns (bytes32 result) {
        assembly {
            // Get free memory pointer
            let ptr := mload(0x40)
            // Store fixed-size parameters
            mstore(ptr, user)
            mstore(add(ptr, 32), usdcAmount)
            // For string, we need to copy the raw bytes
            let chainLen := targetChain.length
            let chainOffset := targetChain.offset
            // Copy string data after the first two words (at offset 64)
            calldatacopy(add(ptr, 64), chainOffset, chainLen)
            // Continue with remaining parameters after string
            let afterChain := add(add(ptr, 64), chainLen)
            mstore(afterChain, expiryDays)
            mstore(add(afterChain, 32), priceGwei)
            mstore(add(afterChain, 64), ethPriceUsd)
            mstore(add(afterChain, 96), ts)
            // Total length: 64 (user + usdcAmount) + chainLen + 128 (4 * 32)
            let totalLen := add(add(64, chainLen), 128)
            result := keccak256(ptr, totalLen)
        }
    }

    /**
     * @notice Hash redeem message parameters using assembly
     * @dev Optimized to avoid abi.encodePacked memory allocation
     */
    function hashRedeemMessage(
        address user,
        uint256 creditId,
        uint256 gasUnitsToUse,
        uint256 currentPriceGwei,
        uint256 ethPriceUsd,
        uint256 ts
    ) internal pure returns (bytes32 result) {
        assembly {
            // Get free memory pointer
            let ptr := mload(0x40)
            // Store all parameters sequentially
            mstore(ptr, user)
            mstore(add(ptr, 32), creditId)
            mstore(add(ptr, 64), gasUnitsToUse)
            mstore(add(ptr, 96), currentPriceGwei)
            mstore(add(ptr, 128), ethPriceUsd)
            mstore(add(ptr, 160), ts)
            // Total: 6 * 32 = 192 bytes
            result := keccak256(ptr, 192)
        }
    }
}
