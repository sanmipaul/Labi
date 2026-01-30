// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IExecutorRegistry} from "./IExecutorRegistry.sol";
import {IReputationManager} from "./IReputationManager.sol";

/**
 * @title ExecutorStaking
 * @notice Facade contract for executor staking operations
 * @dev Provides a unified interface for executor registration and staking
 */
contract ExecutorStaking {
    /// @notice Contract owner
    address public owner;

    /// @notice Executor registry contract
    IExecutorRegistry public executorRegistry;

    /// @notice Reputation manager contract
    IReputationManager public reputationManager;

    /// @notice Minimum reputation score required for high-value flows
    uint256 public minReputationForHighValue = 600;

    /// @notice Minimum stake required for high-value flows
    uint256 public minStakeForHighValue = 2 ether;

    /// @notice Flow value threshold for high-value flows
    uint256 public highValueThreshold = 10 ether;

    /// @notice Emitted when executor eligibility is checked
    event EligibilityChecked(
        address indexed executor,
        bool isEligible,
        uint256 flowValue,
        string reason
    );

    modifier onlyOwner() {
        require(msg.sender == owner, "ExecutorStaking: caller is not owner");
        _;
    }

    constructor(address _executorRegistry, address _reputationManager) {
        require(_executorRegistry != address(0), "ExecutorStaking: invalid registry");
        require(_reputationManager != address(0), "ExecutorStaking: invalid reputation manager");

        owner = msg.sender;
        executorRegistry = IExecutorRegistry(_executorRegistry);
        reputationManager = IReputationManager(_reputationManager);
    }

    /**
     * @notice Check if an executor is eligible to execute a flow
     * @param executor Address of the executor
     * @param flowValue Value of the flow being executed
     * @return isEligible True if eligible
     * @return reason Reason if not eligible
     */
    function checkEligibility(
        address executor,
        uint256 flowValue
    ) external view returns (bool isEligible, string memory reason) {
        // Check if executor is active
        if (!executorRegistry.isActiveExecutor(executor)) {
            return (false, "Executor is not active");
        }

        // Get executor info
        IExecutorRegistry.ExecutorInfo memory info = executorRegistry.getExecutorInfo(executor);

        // Check stake requirements
        uint256 minStake = executorRegistry.getMinimumStake();
        if (info.stakedAmount < minStake) {
            return (false, "Insufficient stake");
        }

        // For high-value flows, check additional requirements
        if (flowValue >= highValueThreshold) {
            // Check reputation threshold
            if (!reputationManager.meetsReputationThreshold(executor, minReputationForHighValue)) {
                return (false, "Insufficient reputation for high-value flow");
            }

            // Check stake threshold for high-value
            if (info.stakedAmount < minStakeForHighValue) {
                return (false, "Insufficient stake for high-value flow");
            }
        }

        return (true, "Eligible");
    }

    /**
     * @notice Get executor's complete status
     * @param executor Address of the executor
     * @return isActive Whether executor is active
     * @return stakedAmount Amount staked
     * @return reputationScore Current reputation score
     * @return tier Current reputation tier
     * @return totalExecutions Total executions performed
     * @return successRate Success rate (in basis points)
     */
    function getExecutorStatus(address executor) external view returns (
        bool isActive,
        uint256 stakedAmount,
        uint256 reputationScore,
        IReputationManager.ReputationTier tier,
        uint256 totalExecutions,
        uint256 successRate
    ) {
        IExecutorRegistry.ExecutorInfo memory info = executorRegistry.getExecutorInfo(executor);
        IReputationManager.ReputationData memory repData = reputationManager.getReputation(executor);

        isActive = info.status == IExecutorRegistry.ExecutorStatus.Active;
        stakedAmount = info.stakedAmount;
        reputationScore = repData.score;
        tier = repData.tier;
        totalExecutions = info.totalExecutions;

        if (info.totalExecutions > 0) {
            successRate = (info.successfulExecutions * 10000) / info.totalExecutions;
        } else {
            successRate = 0;
        }
    }

    /**
     * @notice Get leaderboard data for an executor
     * @param executor Address of the executor
     * @return score Reputation score
     * @return successRate Success rate in basis points
     * @return totalExecutions Total executions
     * @return streak Current streak
     */
    function getLeaderboardData(address executor) external view returns (
        uint256 score,
        uint256 successRate,
        uint256 totalExecutions,
        uint256 streak
    ) {
        IExecutorRegistry.ExecutorInfo memory info = executorRegistry.getExecutorInfo(executor);
        IReputationManager.ReputationData memory repData = reputationManager.getReputation(executor);

        score = repData.score;
        totalExecutions = info.totalExecutions;
        streak = repData.streakCount;

        if (info.totalExecutions > 0) {
            successRate = (info.successfulExecutions * 10000) / info.totalExecutions;
        } else {
            successRate = 0;
        }
    }

    /**
     * @notice Calculate potential earnings based on stake and reputation
     * @param executor Address of the executor
     * @param baseReward Base reward for execution
     * @return potentialReward Potential reward including bonuses
     */
    function calculatePotentialReward(
        address executor,
        uint256 baseReward
    ) external view returns (uint256 potentialReward) {
        IReputationManager.ReputationData memory repData = reputationManager.getReputation(executor);

        // Base reward
        potentialReward = baseReward;

        // Tier bonus
        if (repData.tier == IReputationManager.ReputationTier.Platinum) {
            potentialReward += (baseReward * 2000) / 10000; // +20%
        } else if (repData.tier == IReputationManager.ReputationTier.Gold) {
            potentialReward += (baseReward * 1500) / 10000; // +15%
        } else if (repData.tier == IReputationManager.ReputationTier.Silver) {
            potentialReward += (baseReward * 1000) / 10000; // +10%
        } else if (repData.tier == IReputationManager.ReputationTier.Bronze) {
            potentialReward += (baseReward * 500) / 10000; // +5%
        }

        // Streak bonus (up to 10%)
        uint256 streakBonus = repData.streakCount * 100; // 1% per streak
        if (streakBonus > 1000) streakBonus = 1000;
        potentialReward += (baseReward * streakBonus) / 10000;
    }

    /**
     * @notice Check if executor qualifies for a specific tier
     * @param executor Address of the executor
     * @param requiredTier Required reputation tier
     * @return bool True if executor meets tier requirement
     */
    function meetssTierRequirement(
        address executor,
        IReputationManager.ReputationTier requiredTier
    ) external view returns (bool) {
        IReputationManager.ReputationTier currentTier = reputationManager.getReputationTier(executor);
        return uint8(currentTier) >= uint8(requiredTier);
    }

    // Admin functions

    /**
     * @notice Set minimum reputation for high-value flows
     */
    function setMinReputationForHighValue(uint256 _minRep) external onlyOwner {
        minReputationForHighValue = _minRep;
    }

    /**
     * @notice Set minimum stake for high-value flows
     */
    function setMinStakeForHighValue(uint256 _minStake) external onlyOwner {
        minStakeForHighValue = _minStake;
    }

    /**
     * @notice Set high-value threshold
     */
    function setHighValueThreshold(uint256 _threshold) external onlyOwner {
        highValueThreshold = _threshold;
    }

    /**
     * @notice Update executor registry address
     */
    function setExecutorRegistry(address _registry) external onlyOwner {
        require(_registry != address(0), "ExecutorStaking: invalid registry");
        executorRegistry = IExecutorRegistry(_registry);
    }

    /**
     * @notice Update reputation manager address
     */
    function setReputationManager(address _manager) external onlyOwner {
        require(_manager != address(0), "ExecutorStaking: invalid manager");
        reputationManager = IReputationManager(_manager);
    }
}
