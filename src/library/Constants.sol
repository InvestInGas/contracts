// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title GasConstants
 * @notice Shared constants for the gas futures system
 */
library GasConstants {
    /// @notice Minimum purchase amount in USDC (6 decimals) - $1
    uint256 internal constant MIN_PURCHASE = 1 * 10 ** 6;

    /// @notice Maximum purchase amount in USDC (6 decimals) - $1,000
    uint256 internal constant MAX_PURCHASE = 1_000 * 10 ** 6;

    /// @notice Minimum expiry period - 7 days
    uint256 internal constant MIN_EXPIRY = 7 days;

    /// @notice Maximum expiry period - 90 days
    uint256 internal constant MAX_EXPIRY = 90 days;

    /// @notice Gas units scaling factor (18 decimals for precision)
    uint256 internal constant GAS_UNITS_DECIMALS = 10 ** 18;

    /// @notice Price staleness threshold
    uint256 internal constant PRICE_STALENESS = 5 minutes;

    /// @notice Maximum protocol fee (5%)
    uint256 internal constant MAX_PROTOCOL_FEE_BPS = 500;
}
