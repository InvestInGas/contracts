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
}
