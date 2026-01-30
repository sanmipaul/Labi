// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IReputationManager
 * @notice Interface for executor reputation management
 */
interface IReputationManager {
    /// @notice Reputation tier enum
    enum ReputationTier {
        Novice,      // 0-199 score
        Bronze,      // 200-499 score
        Silver,      // 500-799 score
        Gold,        // 800-949 score
        Platinum     // 950+ score
    }

    /// @notice Reputation data struct
    struct ReputationData {
        uint256 score;
        uint256 totalPoints;
        uint256 penaltyPoints;
        uint256 lastUpdateAt;
        uint256 streakCount;
        uint256 longestStreak;
        ReputationTier tier;
    }

    /// @notice Emitted when reputation score changes
    event ReputationUpdated(
        address indexed executor,
        uint256 oldScore,
        uint256 newScore,
        ReputationTier tier
    );

    /// @notice Emitted when points are awarded
    event PointsAwarded(address indexed executor, uint256 points, string reason);

    /// @notice Emitted when penalty is applied
    event PenaltyApplied(address indexed executor, uint256 penalty, string reason);

    /// @notice Emitted when tier changes
    event TierChanged(address indexed executor, ReputationTier oldTier, ReputationTier newTier);

    /// @notice Emitted when streak is updated
    event StreakUpdated(address indexed executor, uint256 streakCount);

    /**
     * @notice Record a successful execution
     * @param executor Address of the executor
     * @param flowId Flow ID that was executed
     * @param gasUsed Gas used in execution
     */
    function recordSuccessfulExecution(address executor, uint256 flowId, uint256 gasUsed) external;

    /**
     * @notice Record a failed execution
     * @param executor Address of the executor
     * @param flowId Flow ID that failed
     * @param reason Failure reason
     */
    function recordFailedExecution(address executor, uint256 flowId, string calldata reason) external;

    /**
     * @notice Apply a penalty to an executor
     * @param executor Address of the executor
     * @param penalty Penalty points to apply
     * @param reason Reason for penalty
     */
    function applyPenalty(address executor, uint256 penalty, string calldata reason) external;

    /**
     * @notice Get reputation data for an executor
     * @param executor Address of the executor
     * @return ReputationData Reputation details
     */
    function getReputation(address executor) external view returns (ReputationData memory);

    /**
     * @notice Get reputation score for an executor
     * @param executor Address of the executor
     * @return uint256 Reputation score (0-1000)
     */
    function getReputationScore(address executor) external view returns (uint256);

    /**
     * @notice Get reputation tier for an executor
     * @param executor Address of the executor
     * @return ReputationTier Current tier
     */
    function getReputationTier(address executor) external view returns (ReputationTier);

    /**
     * @notice Check if executor meets minimum reputation threshold
     * @param executor Address of the executor
     * @param minimumScore Minimum required score
     * @return bool True if meets threshold
     */
    function meetsReputationThreshold(address executor, uint256 minimumScore) external view returns (bool);

    /**
     * @notice Calculate tier from score
     * @param score Reputation score
     * @return ReputationTier Corresponding tier
     */
    function calculateTier(uint256 score) external pure returns (ReputationTier);
}
