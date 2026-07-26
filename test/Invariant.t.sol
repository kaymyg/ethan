// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {Constitution} from "../src/Constitution.sol";
import {ProposalRegistry} from "../src/ProposalRegistry.sol";
import {Router} from "../src/Router.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockAavePool} from "./mocks/MockAavePool.sol";

contract Handler is Test {
    ProposalRegistry public registry;
    Router public router;
    address public guardian;

    uint256 public executedCount;

    constructor(ProposalRegistry _registry, Router _router, address _guardian) {
        registry = _registry;
        router = _router;
        guardian = _guardian;
    }

    function submit(uint8 action, uint256 amount) external {
        action = uint8(bound(action, 1, 3));
        amount = bound(amount, 1, 100e6);
        try registry.submit(action, amount) {} catch {}
    }

    function warp(uint256 dt) external {
        dt = bound(dt, 1 hours, 80 hours);
        vm.warp(block.timestamp + dt);
    }

    function veto() external {
        uint256 id = registry.activeProposalId();
        if (id == 0) return;
        vm.prank(guardian);
        try registry.veto(id) {} catch {}
    }

    function execute() external {
        uint256 id = registry.activeProposalId();
        if (id == 0) return;
        try router.execute(id) {
            executedCount++;
        } catch {}
    }
}

contract InvariantTest is Test {
    Constitution constitution;
    ProposalRegistry registry;
    Router router;
    MockERC20 usdc;
    MockERC20 aToken;
    MockAavePool pool;
    Handler handler;

    address guardian = makeAddr("guardian");
    address beneficiary = makeAddr("beneficiary");

    uint256 constant INITIAL = 1_000e6;

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        aToken = new MockERC20("Aave Base USDC", "aBasUSDC", 6);
        pool = new MockAavePool(usdc, aToken);
        constitution =
            new Constitution(address(usdc), address(pool), address(aToken), beneficiary, 200, 100e6, 24 hours, 24 hours, 48 hours);
        registry = new ProposalRegistry(constitution, guardian);
        router = new Router(constitution, registry);
        registry.setRouter(address(router));
        usdc.mint(address(router), INITIAL);
        vm.warp(1_000_000);

        handler = new Handler(registry, router, guardian);
        targetContract(address(handler));
    }

    function invariant_FundsConserved() public view {
        assertEq(
            usdc.balanceOf(address(router)) + aToken.balanceOf(address(router)) + usdc.balanceOf(beneficiary),
            INITIAL,
            "funds leaked"
        );
    }

    function invariant_NoStrayBalances() public view {
        assertEq(usdc.balanceOf(address(pool)), aToken.totalSupply(), "pool backing broken");
        assertEq(aToken.totalSupply(), aToken.balanceOf(address(router)), "aTokens escaped router");
    }

    function invariant_DrainBounded() public view {
        assertLe(usdc.balanceOf(beneficiary), handler.executedCount() * 100e6, "drained more than executions allow");
    }

    function invariant_SingleActive() public view {
        uint256 live;
        uint256 n = registry.proposalCount();
        for (uint256 i = 1; i <= n; i++) {
            ProposalRegistry.Proposal memory p = registry.getProposal(i);
            if (p.status == ProposalRegistry.Status.Pending && block.timestamp < p.expiry) live++;
        }
        assertLe(live, 1, "multiple live proposals");
    }
}