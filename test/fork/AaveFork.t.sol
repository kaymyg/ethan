// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Constitution} from "../../src/Constitution.sol";
import {ProposalRegistry} from "../../src/ProposalRegistry.sol";
import {Router} from "../../src/Router.sol";
import {IERC20} from "../../src/interfaces/IERC20.sol";

/// @notice Fork tests: run the REAL Ethan contracts against the REAL Aave v3
///         pool on Base mainnet, replacing the mock 1:1 accounting with Aave's
///         actual liquidity-index math (which rounds).
contract AaveForkTest is Test {
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant AAVE_POOL = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;
    address constant A_TOKEN = 0x4e65fE4DbA92790696d040ac24Aa414708F5c0AB;

    Constitution c;
    ProposalRegistry reg;
    Router router;

    address guardian = makeAddr("guardian");
    address beneficiary = makeAddr("beneficiary");
    address keeper = makeAddr("keeper");

    uint256 constant TIMELOCK = 1 hours;
    uint256 constant WINDOW = 24 hours;
    uint256 constant COOLDOWN = 1 hours;
    uint256 constant SEED = 1_000e6;

    function setUp() public {
        vm.createSelectFork(vm.rpcUrl("base"));
        c = new Constitution(USDC, AAVE_POOL, A_TOKEN, beneficiary, 200, 100e6, COOLDOWN, TIMELOCK, WINDOW);
        reg = new ProposalRegistry(c, guardian);
        router = new Router(c, reg);
        reg.setRouter(address(router));
        deal(USDC, address(router), SEED);
        assertEq(IERC20(USDC).balanceOf(address(router)), SEED, "seed failed");
    }

    function _run(uint8 action, uint256 amount) internal {
        vm.prank(makeAddr("anyProposer"));
        reg.submit(action, amount);
        vm.warp(block.timestamp + TIMELOCK);
        vm.prank(keeper);
        router.execute(reg.activeProposalId());
    }

    function test_Fork_Supply() public {
        _run(1, 10e6);
        uint256 aBal = IERC20(A_TOKEN).balanceOf(address(router));
        assertApproxEqAbs(aBal, 10e6, 5, "aToken not ~= supplied");
        assertEq(IERC20(USDC).balanceOf(address(router)), SEED - 10e6, "liquid wrong");
        assertApproxEqAbs(router.treasuryTotal(), SEED, 5, "treasury not conserved");
        assertEq(IERC20(USDC).allowance(address(router), AAVE_POOL), 0, "allowance not zeroed");
    }

    function test_Fork_RoundingObserved() public {
        _run(1, 200000);
        uint256 aBal = IERC20(A_TOKEN).balanceOf(address(router));
        assertLe(aBal, 200000, "aToken exceeds supplied");
        assertGe(aBal, 200000 - 3, "aToken lost more than rounding dust");
        emit log_named_uint("aToken for 200000 supplied", aBal);
    }

    function test_Fork_SupplyThenWithdraw() public {
        _run(1, 10e6);
        vm.warp(block.timestamp + COOLDOWN);
        _run(2, 9e6);
        assertEq(IERC20(USDC).balanceOf(address(router)), SEED - 10e6 + 9e6, "withdraw did not return USDC");
        assertGe(IERC20(A_TOKEN).balanceOf(address(router)), 1e6 - 5, "residual position wrong");
    }

    function test_Fork_TransferToBeneficiary() public {
        _run(3, 5e6);
        assertEq(IERC20(USDC).balanceOf(beneficiary), 5e6, "beneficiary not paid");
        assertEq(IERC20(USDC).balanceOf(address(router)), SEED - 5e6, "treasury wrong");
    }

    function test_Fork_CapEnforced() public {
        vm.prank(makeAddr("anyProposer"));
        reg.submit(1, 21e6);
        vm.warp(block.timestamp + TIMELOCK);
        uint256 id = reg.activeProposalId();
        vm.prank(keeper);
        vm.expectRevert(Router.AmountExceedsCap.selector);
        router.execute(id);
    }
}