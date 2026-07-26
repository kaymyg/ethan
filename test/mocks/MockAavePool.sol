// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {MockERC20} from "./MockERC20.sol";

/// @notice Minimal Aave v3 Pool mock: 1:1 aToken accounting, no interest.
contract MockAavePool {
    MockERC20 public immutable asset;
    MockERC20 public immutable aToken;

    constructor(MockERC20 asset_, MockERC20 aToken_) {
        asset = asset_;
        aToken = aToken_;
    }

    function supply(address asset_, uint256 amount, address onBehalfOf, uint16) external {
        require(asset_ == address(asset), "wrong asset");
        asset.transferFrom(msg.sender, address(this), amount);
        aToken.mint(onBehalfOf, amount);
    }

    function withdraw(address asset_, uint256 amount, address to) external returns (uint256) {
        require(asset_ == address(asset), "wrong asset");
        aToken.burn(msg.sender, amount);
        asset.transfer(to, amount);
        return amount;
    }
}