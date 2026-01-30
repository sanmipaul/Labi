// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IExecutorRegistry} from "./IExecutorRegistry.sol";
import {IReputationManager} from "./IReputationManager.sol";

/**
 * @title ExecutorSlasher
 * @notice Handles slashing logic for malicious or failed executor behavior
 * @dev Works in conjunction with ExecutorRegistry and ReputationManager
 */
contract ExecutorSlasher {
    /// @notice Contract owner
    address public owner;

    /// @notice Executor registry contract
    IExecutorRegistry public executorRegistry;

    /// @notice Reputation manager contract
    IReputationManager public reputationManager;

    /// @notice Slash percentage for failed execution (in basis points)
    uint256 public failedExecutionSlashBps = 100; // 1%

    /// @notice Slash percentage for malicious behavior (in basis points)
    uint256 public maliciousSlashBps = 5000; // 50%

    /// @notice Slash percentage for timeout (in basis points)
    uint256 public timeoutSlashBps = 200; // 2%

    /// @notice Reputation penalty for failed execution
    uint256 public failedExecutionPenalty = 50;

    /// @notice Reputation penalty for malicious behavior
    uint256 public maliciousPenalty = 500;

    /// @notice Reputation penalty for timeout
    uint256 public timeoutPenalty = 100;

    /// @notice Consecutive failure threshold before auto-suspension
    uint256 public consecutiveFailureThreshold = 5;

    /// @notice Mapping of executor to consecutive failure count
    mapping(address => uint256) public consecutiveFailures;

    /// @notice Authorized slashers
    mapping(address => bool) public authorizedSlashers;

    /// @notice Slashing event types
    enum SlashReason {
        FailedExecution,
        MaliciousBehavior,
        Timeout,
        ManualSlash
    }

    /// @notice Emitted when an executor is slashed
    event ExecutorSlashed(
        address indexed executor,
        SlashReason reason,
        uint256 slashAmount,
        uint256 reputationPenalty
    );

    /// @notice Emitted when executor is auto-suspended
    event ExecutorAutoSuspended(address indexed executor, uint256 consecutiveFailures);

    /// @notice Emitted when slash parameters are updated
    event SlashParametersUpdated(
        uint256 failedSlashBps,
        uint256 maliciousSlashBps,
        uint256 timeoutSlashBps
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "ExecutorSlasher: caller is not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(authorizedSlashers[msg.sender] || msg.sender == owner, "ExecutorSlasher: not authorized");
        _;
    }

    constructor(address _executorRegistry, address _reputationManager) {
        require(_executorRegistry != address(0), "ExecutorSlasher: invalid registry");
        require(_reputationManager != address(0), "ExecutorSlasher: invalid reputation manager");

        owner = msg.sender;
        executorRegistry = IExecutorRegistry(_executorRegistry);
        reputationManager = IReputationManager(_reputationManager);
    }

    /**
     * @notice Slash an executor for failed execution
     * @param executor Address of the executor
     * @param flowId Flow ID that failed
     */
    function slashForFailedExecution(address executor, uint256 flowId) external onlyAuthorized {
        uint256 stakedAmount = executorRegistry.getStakedAmount(executor);
        uint256 slashAmount = (stakedAmount * failedExecutionSlashBps) / 10000;

        // Increment consecutive failures
        consecutiveFailures[executor]++;

        // Apply slash
        if (slashAmount > 0) {
            executorRegistry.slashExecutor(executor, slashAmount, "Failed execution");
        }

        // Apply reputation penalty
        reputationManager.applyPenalty(executor, failedExecutionPenalty, "Failed execution");

        emit ExecutorSlashed(executor, SlashReason.FailedExecution, slashAmount, failedExecutionPenalty);

        // Check for auto-suspension
        if (consecutiveFailures[executor] >= consecutiveFailureThreshold) {
            executorRegistry.suspendExecutor(executor, "Consecutive failures exceeded threshold");
            emit ExecutorAutoSuspended(executor, consecutiveFailures[executor]);
        }
    }

    /**
     * @notice Slash an executor for malicious behavior
     * @param executor Address of the executor
     * @param reason Description of malicious behavior
     */
    function slashForMaliciousBehavior(address executor, string calldata reason) external onlyOwner {
        uint256 stakedAmount = executorRegistry.getStakedAmount(executor);
        uint256 slashAmount = (stakedAmount * maliciousSlashBps) / 10000;

        // Apply heavy slash
        if (slashAmount > 0) {
            executorRegistry.slashExecutor(executor, slashAmount, reason);
        }

        // Apply severe reputation penalty
        reputationManager.applyPenalty(executor, maliciousPenalty, reason);

        emit ExecutorSlashed(executor, SlashReason.MaliciousBehavior, slashAmount, maliciousPenalty);

        // Auto-suspend for malicious behavior
        executorRegistry.suspendExecutor(executor, reason);
    }

    /**
     * @notice Slash an executor for timeout (not executing assigned flows)
     * @param executor Address of the executor
     * @param flowId Flow ID that timed out
     */
    function slashForTimeout(address executor, uint256 flowId) external onlyAuthorized {
        uint256 stakedAmount = executorRegistry.getStakedAmount(executor);
        uint256 slashAmount = (stakedAmount * timeoutSlashBps) / 10000;

        // Apply slash
        if (slashAmount > 0) {
            executorRegistry.slashExecutor(executor, slashAmount, "Execution timeout");
        }

        // Apply reputation penalty
        reputationManager.applyPenalty(executor, timeoutPenalty, "Execution timeout");

        emit ExecutorSlashed(executor, SlashReason.Timeout, slashAmount, timeoutPenalty);
    }

    /**
     * @notice Manual slash by owner
     * @param executor Address of the executor
     * @param slashAmount Amount to slash
     * @param reputationPenalty Reputation penalty to apply
     * @param reason Reason for slashing
     */
    function manualSlash(
        address executor,
        uint256 slashAmount,
        uint256 reputationPenalty,
        string calldata reason
    ) external onlyOwner {
        if (slashAmount > 0) {
            executorRegistry.slashExecutor(executor, slashAmount, reason);
        }

        if (reputationPenalty > 0) {
            reputationManager.applyPenalty(executor, reputationPenalty, reason);
        }

        emit ExecutorSlashed(executor, SlashReason.ManualSlash, slashAmount, reputationPenalty);
    }

    /**
     * @notice Reset consecutive failure count (called on successful execution)
     * @param executor Address of the executor
     */
    function resetConsecutiveFailures(address executor) external onlyAuthorized {
        consecutiveFailures[executor] = 0;
    }

    /**
     * @notice Get consecutive failure count for an executor
     * @param executor Address of the executor
     * @return uint256 Number of consecutive failures
     */
    function getConsecutiveFailures(address executor) external view returns (uint256) {
        return consecutiveFailures[executor];
    }

    /**
     * @notice Calculate potential slash amount for an executor
     * @param executor Address of the executor
     * @param reason Slash reason
     * @return uint256 Potential slash amount
     */
    function calculateSlashAmount(address executor, SlashReason reason) external view returns (uint256) {
        uint256 stakedAmount = executorRegistry.getStakedAmount(executor);

        if (reason == SlashReason.FailedExecution) {
            return (stakedAmount * failedExecutionSlashBps) / 10000;
        } else if (reason == SlashReason.MaliciousBehavior) {
            return (stakedAmount * maliciousSlashBps) / 10000;
        } else if (reason == SlashReason.Timeout) {
            return (stakedAmount * timeoutSlashBps) / 10000;
        }

        return 0;
    }

    // Admin functions

    /**
     * @notice Set failed execution slash percentage
     */
    function setFailedExecutionSlashBps(uint256 _bps) external onlyOwner {
        require(_bps <= 10000, "ExecutorSlasher: invalid bps");
        failedExecutionSlashBps = _bps;
    }

    /**
     * @notice Set malicious slash percentage
     */
    function setMaliciousSlashBps(uint256 _bps) external onlyOwner {
        require(_bps <= 10000, "ExecutorSlasher: invalid bps");
        maliciousSlashBps = _bps;
    }

    /**
     * @notice Set timeout slash percentage
     */
    function setTimeoutSlashBps(uint256 _bps) external onlyOwner {
        require(_bps <= 10000, "ExecutorSlasher: invalid bps");
        timeoutSlashBps = _bps;
    }

    /**
     * @notice Set reputation penalties
     */
    function setReputationPenalties(
        uint256 _failedPenalty,
        uint256 _maliciousPenalty,
        uint256 _timeoutPenalty
    ) external onlyOwner {
        failedExecutionPenalty = _failedPenalty;
        maliciousPenalty = _maliciousPenalty;
        timeoutPenalty = _timeoutPenalty;
    }

    /**
     * @notice Set consecutive failure threshold
     */
    function setConsecutiveFailureThreshold(uint256 _threshold) external onlyOwner {
        consecutiveFailureThreshold = _threshold;
    }

    /**
     * @notice Authorize a slasher
     */
    function setAuthorizedSlasher(address slasher, bool authorized) external onlyOwner {
        authorizedSlashers[slasher] = authorized;
    }

    /**
     * @notice Update executor registry address
     */
    function setExecutorRegistry(address _registry) external onlyOwner {
        require(_registry != address(0), "ExecutorSlasher: invalid registry");
        executorRegistry = IExecutorRegistry(_registry);
    }

    /**
     * @notice Update reputation manager address
     */
    function setReputationManager(address _manager) external onlyOwner {
        require(_manager != address(0), "ExecutorSlasher: invalid manager");
        reputationManager = IReputationManager(_manager);
    }
}
