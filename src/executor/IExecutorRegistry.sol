// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IExecutorRegistry
 * @notice Interface for the executor registration and staking system
 */
interface IExecutorRegistry {
    /// @notice Executor status enum
    enum ExecutorStatus {
        Inactive,
        Active,
        Suspended,
        Slashed
    }

    /// @notice Executor information struct
    struct ExecutorInfo {
        address executor;
        uint256 stakedAmount;
        uint256 registeredAt;
        uint256 lastExecutionAt;
        uint256 totalExecutions;
        uint256 successfulExecutions;
        uint256 failedExecutions;
        ExecutorStatus status;
    }

    /// @notice Emitted when an executor registers
    event ExecutorRegistered(address indexed executor, uint256 stakedAmount);

    /// @notice Emitted when an executor stakes additional tokens
    event ExecutorStakeIncreased(address indexed executor, uint256 additionalStake, uint256 totalStake);

    /// @notice Emitted when an executor withdraws stake
    event ExecutorStakeWithdrawn(address indexed executor, uint256 amount, uint256 remainingStake);

    /// @notice Emitted when an executor is suspended
    event ExecutorSuspended(address indexed executor, string reason);

    /// @notice Emitted when an executor is reactivated
    event ExecutorReactivated(address indexed executor);

    /// @notice Emitted when an executor is slashed
    event ExecutorSlashed(address indexed executor, uint256 slashAmount, string reason);

    /// @notice Emitted when execution is recorded
    event ExecutionRecorded(address indexed executor, uint256 flowId, bool success);

    /**
     * @notice Register as an executor with initial stake
     */
    function registerExecutor() external payable;

    /**
     * @notice Increase stake as an executor
     */
    function increaseStake() external payable;

    /**
     * @notice Withdraw stake (only when inactive or after cooldown)
     * @param amount Amount to withdraw
     */
    function withdrawStake(uint256 amount) external;

    /**
     * @notice Check if an address is a registered active executor
     * @param executor Address to check
     * @return bool True if active executor
     */
    function isActiveExecutor(address executor) external view returns (bool);

    /**
     * @notice Get executor information
     * @param executor Address of the executor
     * @return ExecutorInfo Executor details
     */
    function getExecutorInfo(address executor) external view returns (ExecutorInfo memory);

    /**
     * @notice Get executor's staked amount
     * @param executor Address of the executor
     * @return uint256 Staked amount
     */
    function getStakedAmount(address executor) external view returns (uint256);

    /**
     * @notice Get minimum stake required
     * @return uint256 Minimum stake amount
     */
    function getMinimumStake() external view returns (uint256);

    /**
     * @notice Record an execution (called by FlowExecutor)
     * @param executor Address of the executor
     * @param flowId Flow ID that was executed
     * @param success Whether execution was successful
     */
    function recordExecution(address executor, uint256 flowId, bool success) external;

    /**
     * @notice Suspend an executor
     * @param executor Address to suspend
     * @param reason Reason for suspension
     */
    function suspendExecutor(address executor, string calldata reason) external;

    /**
     * @notice Reactivate a suspended executor
     * @param executor Address to reactivate
     */
    function reactivateExecutor(address executor) external;

    /**
     * @notice Slash an executor's stake
     * @param executor Address to slash
     * @param amount Amount to slash
     * @param reason Reason for slashing
     */
    function slashExecutor(address executor, uint256 amount, string calldata reason) external;
}
