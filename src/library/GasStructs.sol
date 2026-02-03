// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/**
 * @title GasStructs
 * @notice Data structures for gas credit system
 * @dev Uses tight variable packing to reduce storage slots and gas costs
 */
library GasStructs {
    /**
     * @notice Represents a gas credit position (packed into 3 storage slots)
     * @dev Slot 1: lockedPriceGwei (96) + gasUnits (128) + padding (32)
     *      Slot 2: remainingGasUnits (128) + expiry (40) + purchaseTimestamp (40) + isActive (8) + padding (40)
     *      Slot 3: usdcPaid (128) + chainId (8) + padding (120)
     *      Slot 4: targetChain (string - dynamic)
     */
    struct GasCredit {
        // Slot 1
        uint96 lockedPriceGwei;
        uint128 gasUnits;
        // Slot 2
        uint128 remainingGasUnits;
        uint40 expiry;
        uint40 purchaseTimestamp;
        bool isActive;
        // Slot 3
        uint128 usdcPaid;
        // Slot 4
        string targetChain;
    }

    /**
     * @notice Current gas price data for a chain (packed into 2 storage slots)
     * @dev Slot 1: priceGwei (64) + lastUpdate (40) + volatility24h (64) + padding (88)
     *      Slot 2: high24h (64) + low24h (64) + padding (128)
     */
    struct ChainGasPrice {
        uint64 priceGwei;
        uint40 lastUpdate;
        uint64 volatility24h;
        uint64 high24h;
        uint64 low24h;
    }

    /**
     * @notice Options for credit redemption
     * @param cashSettlement If true, receive USDC on Arc. If false, bridge via LiFi.
     * @param lifiData Calldata for LiFi Diamond (only used if cashSettlement is false)
     */
    struct RedemptionOptions {
        bool cashSettlement;
        bytes lifiData;
    }
}
