// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {Constitution} from "../src/Constitution.sol";
import {ProposalRegistry} from "../src/ProposalRegistry.sol";
import {Router} from "../src/Router.sol";

contract Deploy is Script {
    function run() external {
        address usdc = vm.envAddress("USDC");
        address aavePool = vm.envAddress("AAVE_POOL");
        address aToken = vm.envAddress("A_TOKEN");
        address beneficiary = vm.envAddress("BENEFICIARY");
        address guardian = vm.envAddress("GUARDIAN");
        uint256 maxBps = vm.envUint("MAX_BPS");
        uint256 absoluteCap = vm.envUint("ABSOLUTE_CAP");
        uint256 cooldown = vm.envUint("COOLDOWN");
        uint256 timelock = vm.envUint("TIMELOCK");
        uint256 window = vm.envUint("EXECUTION_WINDOW");

        vm.startBroadcast();
        Constitution constitution =
            new Constitution(usdc, aavePool, aToken, beneficiary, maxBps, absoluteCap, cooldown, timelock, window);
        ProposalRegistry registry = new ProposalRegistry(constitution, guardian);
        Router router = new Router(constitution, registry);
        registry.setRouter(address(router));
        vm.stopBroadcast();

        console.log("Constitution:    ", address(constitution));
        console.log("ProposalRegistry:", address(registry));
        console.log("Router (treasury):", address(router));
    }
}