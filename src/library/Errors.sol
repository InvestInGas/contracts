// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title GasErrors
 * @notice Custom errors for the gas futures system
 * @dev Using custom errors saves gas compared to revert strings
 */
library GasErrors {
    // Purchase errors
    error BelowMinimumPurchase();
    error AboveMaximumPurchase();
    error ExpiryTooShort();
    error ExpiryTooLong();
    error ChainNotSupported();
    error PriceStale();

    // Credit errors
    error InvalidCreditId();
    error CreditInactive();
    error CreditExpired();
    error InsufficientGasUnits();
    error NoSavingsAvailable();
    error InvalidRecipient();

    // Access errors
    error NotOracle();
    error FeeTooHigh();

    // Transfer errors
    error TransferFailed();
    error InsufficientContractBalance();

    // LiFi errors
    error LifiNotConfigured();
    error LifiBridgeFailed();
}
