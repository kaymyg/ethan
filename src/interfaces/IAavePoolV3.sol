// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice Minimal Aave v3 Pool interface. Only the two functions Ethan is
///         constitutionally allowed to call.
interface IAavePoolV3 {
    function supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode) external;
    function withdraw(address asset, uint256 amount, address to) external returns (uint256);
}