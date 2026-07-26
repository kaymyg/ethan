// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EthanBase} from "./Base.t.sol";
import {Router} from "../src/Router.sol";
import {ProposalRegistry} from "../src/ProposalRegistry.sol";

contract RouterTest is EthanBase {
    function test_Supply_MovesFundsToAave() public {
        uint256 id = _submitAndWait(1, 20e6);
        vm.prank(keeper);
        router.execute(id);
        assertEq(usdc.balanceOf(address(router)), TREASURY - 20e6);
        assertEq(aToken.balanceOf(address(router)), 20e6);
        assertEq(router.treasuryTotal(), TREASURY);
    }

    function test_Withdraw_BringsFundsBack() public {
        uint256 id = _submitAndWait(1, 20e6);
        vm.prank(keeper);
        router.execute(id);

        vm.warp(block.timestamp + COOLDOWN);
        uint256 id2 = _submitAndWait(2, 20e6);
        vm.prank(keeper);
        router.execute(id2);

        assertEq(usdc.balanceOf(address(router)), TREASURY);
        assertEq(aToken.balanceOf(address(router)), 0);
    }

    function test_Transfer_OnlyToBeneficiary() public {
        uint256 id = _submitAndWait(3, 20e6);
        vm.prank(keeper);
        router.execute(id);
        assertEq(usdc.balanceOf(beneficiary), 20e6);
        assertEq(usdc.balanceOf(address(router)), TREASURY - 20e6);
    }

    function test_CapEnforcedAtExecutionTime() public {
        uint256 id = _submitAndWait(1, 21e6);
        vm.prank(keeper);
        vm.expectRevert(Router.AmountExceedsCap.selector);
        router.execute(id);
    }

    function test_CapTracksShrinkingTreasury() public {
        uint256 id = _submitAndWait(3, 20e6);
        vm.prank(keeper);
        router.execute(id);
        vm.warp(block.timestamp + COOLDOWN);
        uint256 id2 = _submitAndWait(1, 20e6);
        vm.prank(keeper);
        vm.expectRevert(Router.AmountExceedsCap.selector);
        router.execute(id2);
    }

    function test_CooldownViews() public {
        uint256 id = _submitAndWait(1, 10e6);
        vm.prank(keeper);
        router.execute(id);

        uint256 id2 = _submit(2, 5e6);
        vm.warp(block.timestamp + TIMELOCK - 1);
        assertEq(router.cooldownRemaining(), 1);
        vm.warp(block.timestamp + 1);
        assertEq(router.cooldownRemaining(), 0);
        vm.prank(keeper);
        router.execute(id2);
    }

    function test_NoDoubleExecution() public {
        uint256 id = _submitAndWait(1, 10e6);
        vm.prank(keeper);
        router.execute(id);
        vm.warp(block.timestamp + COOLDOWN);
        vm.prank(keeper);
        vm.expectRevert(ProposalRegistry.NotPending.selector);
        router.execute(id);
    }

    function test_AnyoneCanExecute() public {
        uint256 id = _submitAndWait(1, 10e6);
        vm.prank(makeAddr("random-stranger"));
        router.execute(id);
    }

    function test_ApprovalZeroedAfterSupply() public {
        uint256 id = _submitAndWait(1, 10e6);
        vm.prank(keeper);
        router.execute(id);
        assertEq(usdc.allowance(address(router), address(pool)), 0);
    }

    function testFuzz_Execute_RespectsCaps(uint256 amount) public {
        amount = bound(amount, 1, ABSOLUTE_CAP);
        uint256 id = _submitAndWait(1, amount);
        uint256 cap = router.maxExecutionAmount();
        vm.prank(keeper);
        if (amount > cap) {
            vm.expectRevert(Router.AmountExceedsCap.selector);
            router.execute(id);
        } else {
            router.execute(id);
            assertEq(aToken.balanceOf(address(router)), amount);
        }
    }

    function testFuzz_TreasuryConservedBySupplyWithdraw(uint256 a) public {
        a = bound(a, 1, 20e6);
        uint256 before = router.treasuryTotal();
        uint256 id = _submitAndWait(1, a);
        vm.prank(keeper);
        router.execute(id);
        assertEq(router.treasuryTotal(), before);
        vm.warp(block.timestamp + COOLDOWN);
        uint256 id2 = _submitAndWait(2, a);
        vm.prank(keeper);
        router.execute(id2);
        assertEq(router.treasuryTotal(), before);
        assertEq(usdc.balanceOf(address(router)), before);
    }
}