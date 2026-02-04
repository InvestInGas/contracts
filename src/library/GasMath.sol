// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title GasMath
 * @notice Helper library for gas calculations
 */
library GasMath {
    function calculateGasUnits(
        uint256 usdcAmount,
        uint256 feeBps,
        uint256 priceGwei,
        uint256 ethPriceUsd
    ) internal pure returns (uint256 netAmount, uint256 fee, uint256 gasUnits) {
        fee = (usdcAmount * feeBps) / 10000;
        netAmount = usdcAmount - fee;

        // Formula: (USDC * 1e15) / ((GasPriceGwei * ETHPriceUSD) / 1e6)
        // Adjust for decimals: USDC (6), Gwei (9), ETHPrice (6) -> Result (0, wei units)
        gasUnits =
            (netAmount * 10 ** 15) /
            ((priceGwei * ethPriceUsd) / 10 ** 6);
    }

    function calculateSavings(
        uint256 currentPriceGwei,
        uint256 lockedPriceGwei,
        uint256 gasUnitsToUse,
        uint256 ethPriceUsd
    ) internal pure returns (uint256 savedAmount) {
        uint256 priceDiff = currentPriceGwei - lockedPriceGwei;

        // Formula: PriceDiff * GasUnits * ETHPrice
        // Adjust for decimals
        savedAmount =
            (priceDiff * gasUnitsToUse * ethPriceUsd) /
            (10 ** 15 * 10 ** 6);
    }

    function calculateRefund(
        uint256 usdcPaid,
        uint128 remainingGasUnits,
        uint128 initialGasUnits,
        uint256 feeBps
    ) internal pure returns (uint256 refundAmount, uint256 fee) {
        // Calculate proportional value
        uint256 proportionalValue = (uint256(usdcPaid) * remainingGasUnits) /
            initialGasUnits;

        // Calculate fee
        fee = (proportionalValue * feeBps) / 10000;
        refundAmount = proportionalValue - fee;
    }
}
