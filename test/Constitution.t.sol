// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EthanBase} from "./Base.t.sol";
import {Constitution} from "../src/Constitution.sol";

contract ConstitutionTest is EthanBase {
    function test_ImmutableParams() public view {
        assertEq(constitution.USDC(), address(usdc));
        assertEq(constitution.AAVE_POOL(), address(pool));
        assertEq(constitution.A_TOKEN(), address(aToken));
        assertEq(constitution.BENEFICIARY(), beneficiary);
        assertEq(constitution.MAX_BPS(), MAX_BPS);
        assertEq(constitution.ABSOLUTE_CAP(), ABSOLUTE_CAP);
        assertEq(constitution.COOLDOWN(), COOLDOWN);
        assertEq(constitution.TIMELOCK(), TIMELOCK);
        assertEq(constitution.EXECUTION_WINDOW(), WINDOW);
    }

    function test_ValidActions() public view {
        assertTrue(constitution.isValidAction(1));
        assertTrue(constitution.isValidAction(2));
        assertTrue(constitution.isValidAction(3));
        assertFalse(constitution.isValidAction(0));
        assertFalse(constitution.isValidAction(4));
        assertFalse(constitution.isValidAction(255));
    }

    function test_MaxExecutionAmount_BpsBinds() public view {
        assertEq(constitution.maxExecutionAmount(1_000e6), 20e6);
    }

    function test_MaxExecutionAmount_AbsoluteBinds() public view {
        assertEq(constitution.maxExecutionAmount(100_000e6), ABSOLUTE_CAP);
    }

    function test_MaxExecutionAmount_ZeroTreasury() public view {
        assertEq(constitution.maxExecutionAmount(0), 0);
    }

    function test_RevertOn_ZeroAddress() public {
        vm.expectRevert(Constitution.ZeroAddress.selector);
        new Constitution(address(0), address(pool), address(aToken), beneficiary, 200, 100e6, 1, 1, 1);
    }

    function test_RevertOn_BadBps() public {
        vm.expectRevert(Constitution.InvalidParameter.selector);
        new Constitution(address(usdc), address(pool), address(aToken), beneficiary, 0, 100e6, 1, 1, 1);
        vm.expectRevert(Constitution.InvalidParameter.selector);
        new Constitution(address(usdc), address(pool), address(aToken), beneficiary, 10_001, 100e6, 1, 1, 1);
    }

    function test_RevertOn_AbsurdTimings() public {
        vm.expectRevert(Constitution.InvalidParameter.selector);
        new Constitution(address(usdc), address(pool), address(aToken), beneficiary, 200, 100e6, 1, 366 days, 1);
        vm.expectRevert(Constitution.InvalidParameter.selector);
        new Constitution(address(usdc), address(pool), address(aToken), beneficiary, 200, 100e6, 366 days, 1, 1);
        vm.expectRevert(Constitution.InvalidParameter.selector);
        new Constitution(address(usdc), address(pool), address(aToken), beneficiary, 200, 100e6, 1, 1, 366 days);
    }

    function testFuzz_MaxExecutionAmount_NeverExceedsEitherCap(uint256 treasury) public view {
        treasury = bound(treasury, 0, 1e30);
        uint256 cap = constitution.maxExecutionAmount(treasury);
        assertLe(cap, ABSOLUTE_CAP);
        assertLe(cap, (treasury * MAX_BPS) / 10_000);
    }
}