// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Constitution} from "./Constitution.sol";
import {ProposalRegistry} from "./ProposalRegistry.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IAavePoolV3} from "./interfaces/IAavePoolV3.sol";

/// @title Router - the treasury and sole executor of the Ethan protocol (AEP-1)
/// @notice Holds the USDC treasury. Structurally incapable of anything except:
///         SUPPLY into the one Aave v3 pool, WITHDRAW back to itself, and
///         TRANSFER to the one fixed beneficiary. Anyone may trigger execution.
contract Router {
    Constitution public immutable CONSTITUTION;
    ProposalRegistry public immutable REGISTRY;
    IERC20 public immutable USDC;
    IAavePoolV3 public immutable AAVE_POOL;
    IERC20 public immutable A_TOKEN;

    uint256 public lastExecutionTime;

    uint256 private _lock = 1;

    event Executed(uint256 indexed id, uint8 action, uint256 amount, address indexed caller);

    error ZeroAddress();
    error Reentrancy();
    error CooldownActive();
    error AmountExceedsCap();
    error InsufficientLiquid();
    error UnknownAction();
    error ApproveFailed();
    error TransferFailed();
    error WithdrawMismatch();

    modifier nonReentrant() {
        if (_lock != 1) revert Reentrancy();
        _lock = 2;
        _;
        _lock = 1;
    }

    constructor(Constitution constitution, ProposalRegistry registry) {
        if (address(constitution) == address(0) || address(registry) == address(0)) revert ZeroAddress();
        CONSTITUTION = constitution;
        REGISTRY = registry;
        USDC = IERC20(constitution.USDC());
        AAVE_POOL = IAavePoolV3(constitution.AAVE_POOL());
        A_TOKEN = IERC20(constitution.A_TOKEN());
    }

    /// @notice Total treasury value: liquid USDC + Aave position.
    function treasuryTotal() public view returns (uint256) {
        return USDC.balanceOf(address(this)) + A_TOKEN.balanceOf(address(this));
    }

    function maxExecutionAmount() public view returns (uint256) {
        return CONSTITUTION.maxExecutionAmount(treasuryTotal());
    }

    function cooldownRemaining() public view returns (uint256) {
        uint256 readyAt = lastExecutionTime + CONSTITUTION.COOLDOWN();
        return block.timestamp >= readyAt ? 0 : readyAt - block.timestamp;
    }

    /// @notice Execute an eligible proposal. Callable by anyone.
    function execute(uint256 id) external nonReentrant {
        ProposalRegistry.Proposal memory p = REGISTRY.getProposal(id);
        REGISTRY.markExecuted(id);

        if (block.timestamp < lastExecutionTime + CONSTITUTION.COOLDOWN()) revert CooldownActive();
        lastExecutionTime = block.timestamp;

        if (p.amount > CONSTITUTION.maxExecutionAmount(treasuryTotal())) revert AmountExceedsCap();

        if (p.action == CONSTITUTION.ACTION_SUPPLY()) {
            if (USDC.balanceOf(address(this)) < p.amount) revert InsufficientLiquid();
            _approve(address(AAVE_POOL), p.amount);
            AAVE_POOL.supply(address(USDC), p.amount, address(this), 0);
            _approve(address(AAVE_POOL), 0);
        } else if (p.action == CONSTITUTION.ACTION_WITHDRAW()) {
            if (AAVE_POOL.withdraw(address(USDC), p.amount, address(this)) != p.amount) revert WithdrawMismatch();
        } else if (p.action == CONSTITUTION.ACTION_TRANSFER()) {
            if (USDC.balanceOf(address(this)) < p.amount) revert InsufficientLiquid();
            if (!USDC.transfer(CONSTITUTION.BENEFICIARY(), p.amount)) revert TransferFailed();
        } else {
            revert UnknownAction();
        }

        emit Executed(id, p.action, p.amount, msg.sender);
    }

    function _approve(address spender, uint256 amount) internal {
        if (!USDC.approve(spender, amount)) revert ApproveFailed();
    }
}
