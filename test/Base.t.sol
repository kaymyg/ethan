// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Constitution} from "../src/Constitution.sol";
import {ProposalRegistry} from "../src/ProposalRegistry.sol";
import {Router} from "../src/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAavePool} from "./mocks/MockAavePool.sol";

abstract contract EthanBase is Test {
    Constitution internal constitution;
    ProposalRegistry internal registry;
    Router internal router;
    MockERC20 internal usdc;
    MockERC20 internal aToken;
    MockAavePool internal pool;

    address internal guardian = makeAddr("guardian");
    address internal beneficiary = makeAddr("beneficiary");
    address internal proposer = makeAddr("proposer");
    address internal keeper = makeAddr("keeper");

    uint256 internal constant MAX_BPS = 200;
    uint256 internal constant ABSOLUTE_CAP = 100e6;
    uint256 internal constant COOLDOWN = 24 hours;
    uint256 internal constant TIMELOCK = 24 hours;
    uint256 internal constant WINDOW = 48 hours;
    uint256 internal constant TREASURY = 1_000e6;

    function setUp() public virtual {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        aToken = new MockERC20("Aave Base USDC", "aBasUSDC", 6);
        pool = new MockAavePool(usdc, aToken);

        constitution = new Constitution(
            address(usdc), address(pool), address(aToken), beneficiary,
            MAX_BPS, ABSOLUTE_CAP, COOLDOWN, TIMELOCK, WINDOW
        );
        registry = new ProposalRegistry(constitution, guardian);
        router = new Router(constitution, registry);
        registry.setRouter(address(router));

        usdc.mint(address(router), TREASURY);
        vm.warp(1_000_000);
    }

    function _submit(uint8 action, uint256 amount) internal returns (uint256 id) {
        vm.prank(proposer);
        id = registry.submit(action, amount);
    }

    function _submitAndWait(uint8 action, uint256 amount) internal returns (uint256 id) {
        id = _submit(action, amount);
        vm.warp(block.timestamp + TIMELOCK);
    }
}