// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {EthanBase} from "./Base.t.sol";
import {ProposalRegistry} from "../src/ProposalRegistry.sol";

contract ProposalRegistryTest is EthanBase {
    function test_Submit_StoresProposal() public {
        uint256 id = _submit(1, 10e6);
        ProposalRegistry.Proposal memory p = registry.getProposal(id);
        assertEq(p.proposer, proposer);
        assertEq(p.action, 1);
        assertEq(p.amount, 10e6);
        assertEq(p.eta, block.timestamp + TIMELOCK);
        assertEq(p.expiry, block.timestamp + TIMELOCK + WINDOW);
        assertEq(uint8(p.status), uint8(ProposalRegistry.Status.Pending));
        assertEq(registry.activeProposalId(), id);
    }

    function test_Submit_RevertsOnInvalidAction() public {
        vm.expectRevert(ProposalRegistry.InvalidAction.selector);
        registry.submit(0, 10e6);
        vm.expectRevert(ProposalRegistry.InvalidAction.selector);
        registry.submit(4, 10e6);
    }

    function test_Submit_RevertsOnBadAmount() public {
        vm.expectRevert(ProposalRegistry.InvalidAmount.selector);
        registry.submit(1, 0);
        vm.expectRevert(ProposalRegistry.InvalidAmount.selector);
        registry.submit(1, ABSOLUTE_CAP + 1);
    }

    function test_Submit_OnlyOneActive() public {
        _submit(1, 10e6);
        vm.expectRevert(ProposalRegistry.ProposalStillActive.selector);
        registry.submit(1, 5e6);
    }

    function test_Submit_AllowedAfterExpiry() public {
        _submit(1, 10e6);
        vm.warp(block.timestamp + TIMELOCK + WINDOW);
        uint256 id2 = _submit(2, 5e6);
        assertEq(id2, 2);
    }

    function test_Submit_AllowedAfterVeto() public {
        uint256 id = _submit(1, 10e6);
        vm.prank(guardian);
        registry.veto(id);
        uint256 id2 = _submit(2, 5e6);
        assertEq(id2, 2);
    }

    function test_Submit_AllowedAfterExecution() public {
        uint256 id = _submitAndWait(1, 10e6);
        vm.prank(keeper);
        router.execute(id);
        uint256 id2 = _submit(2, 5e6);
        assertEq(id2, 2);
    }

    function test_Veto_OnlyGuardian() public {
        uint256 id = _submit(1, 10e6);
        vm.expectRevert(ProposalRegistry.NotGuardian.selector);
        registry.veto(id);
    }

    function test_Veto_KillsProposal() public {
        uint256 id = _submitAndWait(1, 10e6);
        vm.prank(guardian);
        registry.veto(id);
        vm.prank(keeper);
        vm.expectRevert(ProposalRegistry.NotPending.selector);
        router.execute(id);
    }

    function test_Veto_CannotVetoExecuted() public {
        uint256 id = _submitAndWait(1, 10e6);
        vm.prank(keeper);
        router.execute(id);
        vm.prank(guardian);
        vm.expectRevert(ProposalRegistry.NotPending.selector);
        registry.veto(id);
    }

    function test_RenounceGuardian() public {
        vm.prank(guardian);
        registry.renounceGuardian();
        assertEq(registry.guardian(), address(0));
        uint256 id = _submit(1, 10e6);
        vm.prank(guardian);
        vm.expectRevert(ProposalRegistry.NotGuardian.selector);
        registry.veto(id);
    }

    function test_MarkExecuted_OnlyRouter() public {
        uint256 id = _submitAndWait(1, 10e6);
        vm.expectRevert(ProposalRegistry.NotRouter.selector);
        registry.markExecuted(id);
        vm.prank(guardian);
        vm.expectRevert(ProposalRegistry.NotRouter.selector);
        registry.markExecuted(id);
    }

    function test_SetRouter_OnceOnly() public {
        vm.expectRevert(ProposalRegistry.RouterAlreadySet.selector);
        registry.setRouter(address(0xBEEF));
    }

    function test_SetRouter_OnlyDeployer() public {
        ProposalRegistry fresh = new ProposalRegistry(constitution, guardian);
        vm.prank(proposer);
        vm.expectRevert(ProposalRegistry.NotDeployer.selector);
        fresh.setRouter(address(router));
    }

    function test_IsExecutable_Windows() public {
        uint256 id = _submit(1, 10e6);
        assertFalse(registry.isExecutable(id));
        vm.warp(block.timestamp + TIMELOCK);
        assertTrue(registry.isExecutable(id));
        vm.warp(block.timestamp + WINDOW);
        assertFalse(registry.isExecutable(id));
    }

    function testFuzz_Submit_RejectsAllInvalidActions(uint8 action) public {
        vm.assume(action == 0 || action > 3);
        vm.expectRevert(ProposalRegistry.InvalidAction.selector);
        registry.submit(action, 10e6);
    }

    function testFuzz_TimelockEnforced(uint256 dt) public {
        dt = bound(dt, 0, TIMELOCK - 1);
        uint256 id = _submit(1, 10e6);
        vm.warp(block.timestamp + dt);
        vm.prank(keeper);
        vm.expectRevert(ProposalRegistry.TimelockNotElapsed.selector);
        router.execute(id);
    }

    function testFuzz_ExpiryEnforced(uint256 dt) public {
        dt = bound(dt, TIMELOCK + WINDOW, TIMELOCK + WINDOW + 3650 days);
        uint256 id = _submit(1, 10e6);
        vm.warp(block.timestamp + dt);
        vm.prank(keeper);
        vm.expectRevert(ProposalRegistry.ProposalExpired.selector);
        router.execute(id);
    }
}