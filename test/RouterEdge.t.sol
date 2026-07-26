// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Constitution} from "../src/Constitution.sol";
import {ProposalRegistry} from "../src/ProposalRegistry.sol";
import {Router} from "../src/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAavePool} from "./mocks/MockAavePool.sol";

/// @notice Aave pool mock that tries to re-enter Router.execute on supply.
contract ReentrantPool {
    MockERC20 public asset;
    MockERC20 public aToken;
    Router public router;
    uint256 public reenterId;

    function init(MockERC20 a, MockERC20 at, Router r) external {
        asset = a;
        aToken = at;
        router = r;
    }

    function setReenterId(uint256 id) external {
        reenterId = id;
    }

    function supply(address, uint256 amount, address onBehalfOf, uint16) external {
        asset.transferFrom(msg.sender, address(this), amount);
        aToken.mint(onBehalfOf, amount);
        if (reenterId != 0) router.execute(reenterId);
    }

    function withdraw(address, uint256 amount, address to) external returns (uint256) {
        aToken.burn(msg.sender, amount);
        asset.transfer(to, amount);
        return amount;
    }
}

contract RouterEdgeTest is Test {
    MockERC20 usdc;
    MockERC20 aToken;
    address guardian = makeAddr("guardian");
    address beneficiary = makeAddr("beneficiary");
    address keeper = makeAddr("keeper");

    function _deploy(address pool, uint256 cooldown, uint256 timelock, uint256 window)
        internal
        returns (Constitution c, ProposalRegistry reg, Router r)
    {
        c = new Constitution(address(usdc), pool, address(aToken), beneficiary, 200, 100e6, cooldown, timelock, window);
        reg = new ProposalRegistry(c, guardian);
        r = new Router(c, reg);
        reg.setRouter(address(r));
    }

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        aToken = new MockERC20("Aave Base USDC", "aBasUSDC", 6);
        vm.warp(1_000_000);
    }

    function test_CooldownBinds_WhenLongerThanTimelock() public {
        MockAavePool pool = new MockAavePool(usdc, aToken);
        (, ProposalRegistry reg, Router r) = _deploy(address(pool), 48 hours, 24 hours, 48 hours);
        usdc.mint(address(r), 1_000e6);

        uint256 id = reg.submit(1, 10e6);
        vm.warp(block.timestamp + 24 hours);
        r.execute(id);

        uint256 id2 = reg.submit(2, 5e6);
        vm.warp(block.timestamp + 24 hours);
        vm.prank(keeper);
        vm.expectRevert(Router.CooldownActive.selector);
        r.execute(id2);

        vm.warp(block.timestamp + 24 hours);
        r.execute(id2);
    }

    function test_InsufficientLiquid_Reverts() public {
        MockAavePool pool = new MockAavePool(usdc, aToken);
        (, ProposalRegistry reg, Router r) = _deploy(address(pool), 24 hours, 24 hours, 48 hours);
        aToken.mint(address(r), 10_000e6);
        usdc.mint(address(r), 5e6);

        uint256 id = reg.submit(3, 20e6);
        vm.warp(block.timestamp + 24 hours);
        vm.prank(keeper);
        vm.expectRevert(Router.InsufficientLiquid.selector);
        r.execute(id);
    }

    function test_ReentrancyBlocked() public {
        ReentrantPool evil = new ReentrantPool();
        (, ProposalRegistry reg, Router r) = _deploy(address(evil), 0, 24 hours, 48 hours);
        evil.init(usdc, aToken, r);
        usdc.mint(address(r), 1_000e6);

        uint256 id = reg.submit(1, 10e6);
        evil.setReenterId(id);
        vm.warp(block.timestamp + 24 hours);
        vm.prank(keeper);
        vm.expectRevert(Router.Reentrancy.selector);
        r.execute(id);
    }

    function test_GuardianlessDeployment() public {
        MockAavePool pool = new MockAavePool(usdc, aToken);
        Constitution c =
            new Constitution(address(usdc), address(pool), address(aToken), beneficiary, 200, 100e6, 24 hours, 24 hours, 48 hours);
        ProposalRegistry reg = new ProposalRegistry(c, address(0));
        Router r = new Router(c, reg);
        reg.setRouter(address(r));
        usdc.mint(address(r), 1_000e6);

        uint256 id = reg.submit(1, 10e6);
        vm.warp(block.timestamp + 24 hours);
        r.execute(id);
        assertEq(aToken.balanceOf(address(r)), 10e6);
    }
}
