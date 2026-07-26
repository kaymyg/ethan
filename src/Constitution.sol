// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title Constitution - the immutable rulebook of the Ethan protocol (AEP-1)
/// @notice Every rule is fixed at deployment. There is no owner, no setter,
///         no upgrade path. Changing any rule requires deploying a whole new
///         protocol version and moving funds to it by proposal.
contract Constitution {
    uint8 public constant ACTION_SUPPLY = 1;
    uint8 public constant ACTION_WITHDRAW = 2;
    uint8 public constant ACTION_TRANSFER = 3;

    address public immutable USDC;
    address public immutable AAVE_POOL;
    address public immutable A_TOKEN;
    address public immutable BENEFICIARY;

    uint256 public immutable MAX_BPS;
    uint256 public immutable ABSOLUTE_CAP;
    uint256 public immutable COOLDOWN;
    uint256 public immutable TIMELOCK;
    uint256 public immutable EXECUTION_WINDOW;

    uint256 internal constant BPS_DENOMINATOR = 10_000;

    error ZeroAddress();
    error InvalidParameter();

    constructor(
        address usdc,
        address aavePool,
        address aToken,
        address beneficiary,
        uint256 maxBps,
        uint256 absoluteCap,
        uint256 cooldown,
        uint256 timelock,
        uint256 executionWindow
    ) {
        if (usdc == address(0) || aavePool == address(0) || aToken == address(0) || beneficiary == address(0)) {
            revert ZeroAddress();
        }
        if (maxBps == 0 || maxBps > BPS_DENOMINATOR) revert InvalidParameter();
        if (absoluteCap == 0) revert InvalidParameter();
        if (timelock == 0 || executionWindow == 0) revert InvalidParameter();
        // Hard upper bounds keep uint64 timestamp math safe and rule out
        // absurd deployments (nothing may be locked in for over a year).
        if (timelock > 365 days || executionWindow > 365 days || cooldown > 365 days) revert InvalidParameter();

        USDC = usdc;
        AAVE_POOL = aavePool;
        A_TOKEN = aToken;
        BENEFICIARY = beneficiary;
        MAX_BPS = maxBps;
        ABSOLUTE_CAP = absoluteCap;
        COOLDOWN = cooldown;
        TIMELOCK = timelock;
        EXECUTION_WINDOW = executionWindow;
    }

    function isValidAction(uint8 action) public pure returns (bool) {
        return action == ACTION_SUPPLY || action == ACTION_WITHDRAW || action == ACTION_TRANSFER;
    }

    /// @notice The largest amount a single execution may move, given the
    ///         current total treasury value (liquid USDC + aToken balance).
    function maxExecutionAmount(uint256 treasuryTotal) public view returns (uint256) {
        uint256 bpsCap = (treasuryTotal * MAX_BPS) / BPS_DENOMINATOR;
        return bpsCap < ABSOLUTE_CAP ? bpsCap : ABSOLUTE_CAP;
    }
}