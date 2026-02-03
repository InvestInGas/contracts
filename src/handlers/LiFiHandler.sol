// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {GasErrors} from "../library/Errors.sol";

abstract contract LiFiHandler {
    address public lifiDiamond;
    IERC20 internal immutable _usdc;

    event LiFiBridgeExecuted(
        address indexed user,
        uint256 amount,
        string targetChain
    );

    event LifiDiamondUpdated(
        address indexed oldDiamond,
        address indexed newDiamond
    );

    constructor(address usdc_) {
        _usdc = IERC20(usdc_);
    }

    function _executeLifiBridge(
        uint256 amount,
        bytes memory lifiData,
        string memory targetChain
    ) internal {
        if (lifiDiamond == address(0)) revert GasErrors.LifiNotConfigured();
        if (lifiData.length == 0) revert GasErrors.LifiBridgeFailed();

        _usdc.approve(lifiDiamond, amount);

        (bool success, ) = lifiDiamond.call(lifiData);
        if (!success) revert GasErrors.LifiBridgeFailed();

        emit LiFiBridgeExecuted(msg.sender, amount, targetChain);
    }

    function _setLifiDiamond(address _newDiamond) internal {
        address oldDiamond = lifiDiamond;
        lifiDiamond = _newDiamond;
        emit LifiDiamondUpdated(oldDiamond, _newDiamond);
    }
}
