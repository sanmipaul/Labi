// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IExecutorRegistry} from "./IExecutorRegistry.sol";

/**
 * @title ExecutorRegistry
 * @notice Manages executor registration, staking, and basic status tracking
 * @dev Executors must stake tokens to participate in flow execution
 */
contract ExecutorRegistry is IExecutorRegistry {
    /// @notice Contract owner
    address public owner;

    /// @notice Minimum stake required to register as executor
    uint256 public minimumStake;

    /// @notice Cooldown period before stake can be withdrawn (in seconds)
    uint256 public withdrawalCooldown;

    /// @notice Mapping of executor addresses to their info
    mapping(address => ExecutorInfo) private executors;

    /// @notice Mapping of executor addresses to withdrawal request timestamps
    mapping(address => uint256) private withdrawalRequests;

    /// @notice List of all registered executor addresses
    address[] private executorList;

    /// @notice Authorized callers that can record executions
    mapping(address => bool) public authorizedCallers;

    /// @notice Treasury address for slashed funds
    address public treasury;

    modifier onlyOwner() {
        require(msg.sender == owner, "ExecutorRegistry: caller is not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(authorizedCallers[msg.sender] || msg.sender == owner, "ExecutorRegistry: not authorized");
        _;
    }

    constructor(uint256 _minimumStake, uint256 _withdrawalCooldown, address _treasury) {
        require(_treasury != address(0), "ExecutorRegistry: invalid treasury");
        owner = msg.sender;
        minimumStake = _minimumStake;
        withdrawalCooldown = _withdrawalCooldown;
        treasury = _treasury;
    }

    /**
     * @notice Register as an executor with initial stake
     * @dev Must send at least minimumStake ETH
     */
    function registerExecutor() external payable override {
        require(msg.value >= minimumStake, "ExecutorRegistry: insufficient stake");
        require(executors[msg.sender].executor == address(0), "ExecutorRegistry: already registered");

        executors[msg.sender] = ExecutorInfo({
            executor: msg.sender,
            stakedAmount: msg.value,
            registeredAt: block.timestamp,
            lastExecutionAt: 0,
            totalExecutions: 0,
            successfulExecutions: 0,
            failedExecutions: 0,
            status: ExecutorStatus.Active
        });

        executorList.push(msg.sender);

        emit ExecutorRegistered(msg.sender, msg.value);
    }

    /**
     * @notice Increase stake as an executor
     */
    function increaseStake() external payable override {
        require(executors[msg.sender].executor != address(0), "ExecutorRegistry: not registered");
        require(msg.value > 0, "ExecutorRegistry: zero stake increase");

        executors[msg.sender].stakedAmount += msg.value;

        emit ExecutorStakeIncreased(msg.sender, msg.value, executors[msg.sender].stakedAmount);
    }

    /**
     * @notice Request stake withdrawal (starts cooldown)
     */
    function requestWithdrawal() external {
        require(executors[msg.sender].executor != address(0), "ExecutorRegistry: not registered");
        require(withdrawalRequests[msg.sender] == 0, "ExecutorRegistry: withdrawal already requested");

        withdrawalRequests[msg.sender] = block.timestamp;

        // Set status to inactive when withdrawal is requested
        executors[msg.sender].status = ExecutorStatus.Inactive;
    }

    /**
     * @notice Withdraw stake after cooldown period
     * @param amount Amount to withdraw
     */
    function withdrawStake(uint256 amount) external override {
        ExecutorInfo storage executor = executors[msg.sender];

        require(executor.executor != address(0), "ExecutorRegistry: not registered");
        require(executor.status != ExecutorStatus.Slashed, "ExecutorRegistry: executor is slashed");
        require(amount > 0, "ExecutorRegistry: zero withdrawal");
        require(amount <= executor.stakedAmount, "ExecutorRegistry: insufficient stake");

        // Check cooldown
        uint256 requestTime = withdrawalRequests[msg.sender];
        require(requestTime > 0, "ExecutorRegistry: withdrawal not requested");
        require(block.timestamp >= requestTime + withdrawalCooldown, "ExecutorRegistry: cooldown not elapsed");

        executor.stakedAmount -= amount;

        // Reset withdrawal request
        withdrawalRequests[msg.sender] = 0;

        // Transfer ETH to executor
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "ExecutorRegistry: transfer failed");

        emit ExecutorStakeWithdrawn(msg.sender, amount, executor.stakedAmount);
    }

    /**
     * @notice Check if an address is a registered active executor
     */
    function isActiveExecutor(address executor) external view override returns (bool) {
        return executors[executor].status == ExecutorStatus.Active;
    }

    /**
     * @notice Get executor information
     */
    function getExecutorInfo(address executor) external view override returns (ExecutorInfo memory) {
        return executors[executor];
    }

    /**
     * @notice Get executor's staked amount
     */
    function getStakedAmount(address executor) external view override returns (uint256) {
        return executors[executor].stakedAmount;
    }

    /**
     * @notice Get minimum stake required
     */
    function getMinimumStake() external view override returns (uint256) {
        return minimumStake;
    }

    /**
     * @notice Record an execution
     */
    function recordExecution(address executor, uint256 flowId, bool success) external override onlyAuthorized {
        ExecutorInfo storage info = executors[executor];
        require(info.executor != address(0), "ExecutorRegistry: executor not registered");

        info.totalExecutions++;
        info.lastExecutionAt = block.timestamp;

        if (success) {
            info.successfulExecutions++;
        } else {
            info.failedExecutions++;
        }

        emit ExecutionRecorded(executor, flowId, success);
    }

    /**
     * @notice Suspend an executor
     */
    function suspendExecutor(address executor, string calldata reason) external override onlyOwner {
        require(executors[executor].executor != address(0), "ExecutorRegistry: not registered");
        require(executors[executor].status == ExecutorStatus.Active, "ExecutorRegistry: not active");

        executors[executor].status = ExecutorStatus.Suspended;

        emit ExecutorSuspended(executor, reason);
    }

    /**
     * @notice Reactivate a suspended executor
     */
    function reactivateExecutor(address executor) external override onlyOwner {
        require(executors[executor].executor != address(0), "ExecutorRegistry: not registered");
        require(executors[executor].status == ExecutorStatus.Suspended, "ExecutorRegistry: not suspended");
        require(executors[executor].stakedAmount >= minimumStake, "ExecutorRegistry: insufficient stake");

        executors[executor].status = ExecutorStatus.Active;

        emit ExecutorReactivated(executor);
    }

    /**
     * @notice Slash an executor's stake
     */
    function slashExecutor(address executor, uint256 amount, string calldata reason) external override onlyOwner {
        ExecutorInfo storage info = executors[executor];
        require(info.executor != address(0), "ExecutorRegistry: not registered");
        require(amount <= info.stakedAmount, "ExecutorRegistry: slash exceeds stake");

        info.stakedAmount -= amount;
        info.status = ExecutorStatus.Slashed;

        // Transfer slashed funds to treasury
        (bool success, ) = treasury.call{value: amount}("");
        require(success, "ExecutorRegistry: treasury transfer failed");

        emit ExecutorSlashed(executor, amount, reason);
    }

    // Admin functions

    /**
     * @notice Set minimum stake requirement
     */
    function setMinimumStake(uint256 _minimumStake) external onlyOwner {
        minimumStake = _minimumStake;
    }

    /**
     * @notice Set withdrawal cooldown period
     */
    function setWithdrawalCooldown(uint256 _cooldown) external onlyOwner {
        withdrawalCooldown = _cooldown;
    }

    /**
     * @notice Authorize a caller to record executions
     */
    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        authorizedCallers[caller] = authorized;
    }

    /**
     * @notice Set treasury address
     */
    function setTreasury(address _treasury) external onlyOwner {
        require(_treasury != address(0), "ExecutorRegistry: invalid treasury");
        treasury = _treasury;
    }

    /**
     * @notice Get total number of registered executors
     */
    function getTotalExecutors() external view returns (uint256) {
        return executorList.length;
    }

    /**
     * @notice Get executor address by index
     */
    function getExecutorByIndex(uint256 index) external view returns (address) {
        require(index < executorList.length, "ExecutorRegistry: index out of bounds");
        return executorList[index];
    }
}
