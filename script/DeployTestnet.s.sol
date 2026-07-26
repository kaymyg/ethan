// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Constitution} from "../src/Constitution.sol";
import {ProposalRegistry} from "../src/ProposalRegistry.sol";
import {Router} from "../src/Router.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";
import {MockAavePool} from "../test/mocks/MockAavePool.sol";

contract DeployTestnet is Script {
    function run() external {
        address beneficiary = vm.envAddress("BENEFICIARY");
        address guardian = vm.envAddress("GUARDIAN");

        vm.startBroadcast();
        MockERC20 usdc = new MockERC20("Test USDC", "tUSDC", 6);
        MockERC20 aToken = new MockERC20("Test aUSDC", "taUSDC", 6);
        MockAavePool pool = new MockAavePool(usdc, aToken);

        Constitution constitution = new Constitution(
            address(usdc),
            address(pool),
            address(aToken),
            beneficiary,
            200,
            100e6,
            10 minutes,
            10 minutes,
            2 hours
        );
        ProposalRegistry registry = new ProposalRegistry(constitution, guardian);
        Router router = new Router(constitution, registry);
        registry.setRouter(address(router));

        usdc.mint(address(router), 1_000e6);
        vm.stopBroadcast();

        console.log("tUSDC:           ", address(usdc));
        console.log("MockAavePool:    ", address(pool));
        console.log("Constitution:    ", address(constitution));
        console.log("ProposalRegistry:", address(registry));
        console.log("Router (treasury):", address(router));
    }
}