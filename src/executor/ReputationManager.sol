// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IReputationManager} from "./IReputationManager.sol";

/**
 * @title ReputationManager
 * @notice Manages executor reputation scores based on execution performance
 * @dev Score ranges from 0-1000, with tiers determining executor privileges
 */
contract ReputationManager is IReputationManager {
    /// @notice Contract owner
    address public owner;

    /// @notice Base points for successful execution
    uint256 public baseSuccessPoints = 10;

    /// @notice Base penalty for failed execution
    uint256 public baseFailurePenalty = 20;

    /// @notice Bonus multiplier for gas efficiency (in basis points)
    uint256 public gasEfficiencyBonus = 100; // 1%

    /// @notice Streak bonus points
    uint256 public streakBonus = 5;

    /// @notice Maximum reputation score
    uint256 public constant MAX_SCORE = 1000;

    /// @notice Initial reputation score for new executors
    uint256 public constant INITIAL_SCORE = 500;

    /// @notice Mapping of executor addresses to reputation data
    mapping(address => ReputationData) private reputations;

    /// @notice Authorized callers that can update reputation
    mapping(address => bool) public authorizedCallers;

    /// @notice Tier thresholds
    uint256 public constant BRONZE_THRESHOLD = 200;
    uint256 public constant SILVER_THRESHOLD = 500;
    uint256 public constant GOLD_THRESHOLD = 800;
    uint256 public constant PLATINUM_THRESHOLD = 950;

    modifier onlyOwner() {
        require(msg.sender == owner, "ReputationManager: caller is not owner");
        _;
    }

    modifier onlyAuthorized() {
        require(authorizedCallers[msg.sender] || msg.sender == owner, "ReputationManager: not authorized");
        _;
    }

    constructor() {
        owner = msg.sender;
    }

    /**
     * @notice Initialize reputation for a new executor
     * @param executor Address of the executor
     */
    function initializeReputation(address executor) external onlyAuthorized {
        require(reputations[executor].lastUpdateAt == 0, "ReputationManager: already initialized");

        reputations[executor] = ReputationData({
            score: INITIAL_SCORE,
            totalPoints: INITIAL_SCORE,
            penaltyPoints: 0,
            lastUpdateAt: block.timestamp,
            streakCount: 0,
            longestStreak: 0,
            tier: ReputationTier.Silver // 500 is Silver tier
        });

        emit ReputationUpdated(executor, 0, INITIAL_SCORE, ReputationTier.Silver);
    }

    /**
     * @notice Record a successful execution
     */
    function recordSuccessfulExecution(
        address executor,
        uint256 flowId,
        uint256 gasUsed
    ) external override onlyAuthorized {
        ReputationData storage rep = reputations[executor];

        // Initialize if new executor
        if (rep.lastUpdateAt == 0) {
            rep.score = INITIAL_SCORE;
            rep.totalPoints = INITIAL_SCORE;
            rep.lastUpdateAt = block.timestamp;
            rep.tier = ReputationTier.Silver;
        }

        uint256 oldScore = rep.score;
        ReputationTier oldTier = rep.tier;

        // Calculate points
        uint256 points = baseSuccessPoints;

        // Add gas efficiency bonus (if gas used is below average)
        if (gasUsed < 200000) {
            points += (baseSuccessPoints * gasEfficiencyBonus) / 10000;
        }

        // Update streak
        rep.streakCount++;
        if (rep.streakCount > rep.longestStreak) {
            rep.longestStreak = rep.streakCount;
        }

        // Add streak bonus
        if (rep.streakCount >= 5) {
            points += streakBonus;
        }
        if (rep.streakCount >= 10) {
            points += streakBonus;
        }
        if (rep.streakCount >= 25) {
            points += streakBonus * 2;
        }

        // Update points
        rep.totalPoints += points;

        // Calculate new score
        rep.score = _calculateScore(rep.totalPoints, rep.penaltyPoints);
        rep.lastUpdateAt = block.timestamp;

        // Update tier
        ReputationTier newTier = calculateTier(rep.score);
        rep.tier = newTier;

        emit PointsAwarded(executor, points, "Successful execution");
        emit StreakUpdated(executor, rep.streakCount);

        if (rep.score != oldScore) {
            emit ReputationUpdated(executor, oldScore, rep.score, newTier);
        }

        if (newTier != oldTier) {
            emit TierChanged(executor, oldTier, newTier);
        }
    }

    /**
     * @notice Record a failed execution
     */
    function recordFailedExecution(
        address executor,
        uint256 flowId,
        string calldata reason
    ) external override onlyAuthorized {
        ReputationData storage rep = reputations[executor];

        if (rep.lastUpdateAt == 0) {
            rep.score = INITIAL_SCORE;
            rep.totalPoints = INITIAL_SCORE;
            rep.lastUpdateAt = block.timestamp;
            rep.tier = ReputationTier.Silver;
        }

        uint256 oldScore = rep.score;
        ReputationTier oldTier = rep.tier;

        // Reset streak
        rep.streakCount = 0;

        // Apply penalty
        rep.penaltyPoints += baseFailurePenalty;

        // Calculate new score
        rep.score = _calculateScore(rep.totalPoints, rep.penaltyPoints);
        rep.lastUpdateAt = block.timestamp;

        // Update tier
        ReputationTier newTier = calculateTier(rep.score);
        rep.tier = newTier;

        emit PenaltyApplied(executor, baseFailurePenalty, reason);
        emit StreakUpdated(executor, 0);

        if (rep.score != oldScore) {
            emit ReputationUpdated(executor, oldScore, rep.score, newTier);
        }

        if (newTier != oldTier) {
            emit TierChanged(executor, oldTier, newTier);
        }
    }

    /**
     * @notice Apply a penalty to an executor
     */
    function applyPenalty(
        address executor,
        uint256 penalty,
        string calldata reason
    ) external override onlyAuthorized {
        ReputationData storage rep = reputations[executor];
        require(rep.lastUpdateAt > 0, "ReputationManager: executor not initialized");

        uint256 oldScore = rep.score;
        ReputationTier oldTier = rep.tier;

        rep.penaltyPoints += penalty;
        rep.streakCount = 0;

        // Calculate new score
        rep.score = _calculateScore(rep.totalPoints, rep.penaltyPoints);
        rep.lastUpdateAt = block.timestamp;

        // Update tier
        ReputationTier newTier = calculateTier(rep.score);
        rep.tier = newTier;

        emit PenaltyApplied(executor, penalty, reason);

        if (rep.score != oldScore) {
            emit ReputationUpdated(executor, oldScore, rep.score, newTier);
        }

        if (newTier != oldTier) {
            emit TierChanged(executor, oldTier, newTier);
        }
    }

    /**
     * @notice Get reputation data for an executor
     */
    function getReputation(address executor) external view override returns (ReputationData memory) {
        return reputations[executor];
    }

    /**
     * @notice Get reputation score for an executor
     */
    function getReputationScore(address executor) external view override returns (uint256) {
        if (reputations[executor].lastUpdateAt == 0) {
            return INITIAL_SCORE;
        }
        return reputations[executor].score;
    }

    /**
     * @notice Get reputation tier for an executor
     */
    function getReputationTier(address executor) external view override returns (ReputationTier) {
        if (reputations[executor].lastUpdateAt == 0) {
            return ReputationTier.Silver;
        }
        return reputations[executor].tier;
    }

    /**
     * @notice Check if executor meets minimum reputation threshold
     */
    function meetsReputationThreshold(
        address executor,
        uint256 minimumScore
    ) external view override returns (bool) {
        if (reputations[executor].lastUpdateAt == 0) {
            return INITIAL_SCORE >= minimumScore;
        }
        return reputations[executor].score >= minimumScore;
    }

    /**
     * @notice Calculate tier from score
     */
    function calculateTier(uint256 score) public pure override returns (ReputationTier) {
        if (score >= PLATINUM_THRESHOLD) {
            return ReputationTier.Platinum;
        } else if (score >= GOLD_THRESHOLD) {
            return ReputationTier.Gold;
        } else if (score >= SILVER_THRESHOLD) {
            return ReputationTier.Silver;
        } else if (score >= BRONZE_THRESHOLD) {
            return ReputationTier.Bronze;
        } else {
            return ReputationTier.Novice;
        }
    }

    /**
     * @dev Calculate score from total points and penalties
     */
    function _calculateScore(uint256 totalPoints, uint256 penaltyPoints) private pure returns (uint256) {
        if (penaltyPoints >= totalPoints) {
            return 0;
        }

        uint256 netPoints = totalPoints - penaltyPoints;

        // Normalize to 0-1000 scale
        // Using logarithmic scaling for diminishing returns
        if (netPoints >= MAX_SCORE) {
            return MAX_SCORE;
        }

        return netPoints > MAX_SCORE ? MAX_SCORE : netPoints;
    }

    // Admin functions

    /**
     * @notice Set base success points
     */
    function setBaseSuccessPoints(uint256 _points) external onlyOwner {
        baseSuccessPoints = _points;
    }

    /**
     * @notice Set base failure penalty
     */
    function setBaseFailurePenalty(uint256 _penalty) external onlyOwner {
        baseFailurePenalty = _penalty;
    }

    /**
     * @notice Set gas efficiency bonus
     */
    function setGasEfficiencyBonus(uint256 _bonus) external onlyOwner {
        gasEfficiencyBonus = _bonus;
    }

    /**
     * @notice Set streak bonus
     */
    function setStreakBonus(uint256 _bonus) external onlyOwner {
        streakBonus = _bonus;
    }

    /**
     * @notice Authorize a caller to update reputation
     */
    function setAuthorizedCaller(address caller, bool authorized) external onlyOwner {
        authorizedCallers[caller] = authorized;
    }
}
