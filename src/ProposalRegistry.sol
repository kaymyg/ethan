// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Constitution} from "./Constitution.sol";

/// @title ProposalRegistry - the lifecycle ledger of the Ethan protocol (AEP-1)
/// @notice Anyone may submit a proposal that conforms to the Constitution.
///         One proposal is active at a time. After the timelock it becomes
///         executable (by the Router only) for a fixed window, then expires.
///         The guardian may only veto pending proposals, and can be renounced.
contract ProposalRegistry {
    enum Status {
        None,
        Pending,
        Executed,
        Vetoed
    }

    struct Proposal {
        address proposer;
        uint8 action;
        uint256 amount;
        uint64 eta;
        uint64 expiry;
        Status status;
    }

    Constitution public immutable CONSTITUTION;

    address public guardian;
    address public router;
    address private immutable _deployer;

    uint256 public proposalCount;
    uint256 public activeProposalId;

    event ProposalSubmitted(
        uint256 indexed id, address indexed proposer, uint8 action, uint256 amount, uint64 eta, uint64 expiry
    );
    event ProposalVetoed(uint256 indexed id, address indexed guardian);
    event ProposalExecuted(uint256 indexed id);
    event GuardianRenounced(address indexed formerGuardian);
    event RouterSet(address indexed router);

    error NotGuardian();
    error NotRouter();
    error NotDeployer();
    error RouterAlreadySet();
    error ZeroAddress();
    error InvalidAction();
    error InvalidAmount();
    error ProposalStillActive();
    error NotPending();
    error TimelockNotElapsed();
    error ProposalExpired();

    mapping(uint256 => Proposal) internal _proposals;

    constructor(Constitution constitution, address guardian_) {
        if (address(constitution) == address(0)) revert ZeroAddress();
        CONSTITUTION = constitution;
        guardian = guardian_;
        _deployer = msg.sender;
    }

    /// @notice One-time wiring of the Router, callable only by the deployer.
    function setRouter(address router_) external {
        if (msg.sender != _deployer) revert NotDeployer();
        if (router != address(0)) revert RouterAlreadySet();
        if (router_ == address(0)) revert ZeroAddress();
        router = router_;
        emit RouterSet(router_);
    }

    /// @notice Submit a proposal. Anyone may call. Constitution decides validity.
    function submit(uint8 action, uint256 amount) external returns (uint256 id) {
        if (!CONSTITUTION.isValidAction(action)) revert InvalidAction();
        if (amount == 0 || amount > CONSTITUTION.ABSOLUTE_CAP()) revert InvalidAmount();

        uint256 activeId = activeProposalId;
        if (activeId != 0) {
            Proposal storage active = _proposals[activeId];
            if (active.status == Status.Pending && block.timestamp < active.expiry) {
                revert ProposalStillActive();
            }
        }

        uint64 eta = uint64(block.timestamp + CONSTITUTION.TIMELOCK());
        uint64 expiry = uint64(uint256(eta) + CONSTITUTION.EXECUTION_WINDOW());

        id = ++proposalCount;
        _proposals[id] = Proposal({
            proposer: msg.sender,
            action: action,
            amount: amount,
            eta: eta,
            expiry: expiry,
            status: Status.Pending
        });
        activeProposalId = id;

        emit ProposalSubmitted(id, msg.sender, action, amount, eta, expiry);
    }

    /// @notice Guardian cancels a pending proposal. Its only power.
    function veto(uint256 id) external {
        if (msg.sender != guardian) revert NotGuardian();
        Proposal storage p = _proposals[id];
        if (p.status != Status.Pending) revert NotPending();
        p.status = Status.Vetoed;
        emit ProposalVetoed(id, msg.sender);
    }

    /// @notice Guardian gives up the veto power forever.
    function renounceGuardian() external {
        if (msg.sender != guardian) revert NotGuardian();
        guardian = address(0);
        emit GuardianRenounced(msg.sender);
    }

    /// @notice Router-only: atomically checks eligibility and consumes the proposal.
    function markExecuted(uint256 id) external {
        if (msg.sender != router) revert NotRouter();
        Proposal storage p = _proposals[id];
        if (p.status != Status.Pending) revert NotPending();
        if (block.timestamp < p.eta) revert TimelockNotElapsed();
        if (block.timestamp >= p.expiry) revert ProposalExpired();
        p.status = Status.Executed;
        emit ProposalExecuted(id);
    }

    function getProposal(uint256 id) external view returns (Proposal memory) {
        return _proposals[id];
    }

    function isExecutable(uint256 id) external view returns (bool) {
        Proposal storage p = _proposals[id];
        return p.status == Status.Pending && block.timestamp >= p.eta && block.timestamp < p.expiry;
    }
}