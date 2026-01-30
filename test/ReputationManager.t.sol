// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/executor/ReputationManager.sol";

contract ReputationManagerTest is Test {
    ReputationManager public reputationManager;
    address public owner;
    address public executor1;
    address public executor2;

    event ReputationUpdated(address indexed executor, uint256 oldScore, uint256 newScore, IReputationManager.ReputationTier tier);
    event PointsAwarded(address indexed executor, uint256 points, string reason);
    event PenaltyApplied(address indexed executor, uint256 penalty, string reason);
    event TierChanged(address indexed executor, IReputationManager.ReputationTier oldTier, IReputationManager.ReputationTier newTier);
    event StreakUpdated(address indexed executor, uint256 streakCount);

    function setUp() public {
        owner = address(this);
        executor1 = makeAddr("executor1");
        executor2 = makeAddr("executor2");

        reputationManager = new ReputationManager();
        reputationManager.setAuthorizedCaller(address(this), true);
    }

    function test_InitializeReputation() public {
        reputationManager.initializeReputation(executor1);

        IReputationManager.ReputationData memory data = reputationManager.getReputation(executor1);

        assertEq(data.score, 500);
        assertEq(data.totalPoints, 500);
        assertEq(data.penaltyPoints, 0);
        assertEq(uint8(data.tier), uint8(IReputationManager.ReputationTier.Silver));
    }

    function test_RecordSuccessfulExecution() public {
        reputationManager.initializeReputation(executor1);

        uint256 initialScore = reputationManager.getReputationScore(executor1);

        reputationManager.recordSuccessfulExecution(executor1, 1, 100000);

        uint256 newScore = reputationManager.getReputationScore(executor1);
        assertTrue(newScore > initialScore);

        IReputationManager.ReputationData memory data = reputationManager.getReputation(executor1);
        assertEq(data.streakCount, 1);
    }

    function test_RecordFailedExecution() public {
        reputationManager.initializeReputation(executor1);

        uint256 initialScore = reputationManager.getReputationScore(executor1);

        reputationManager.recordFailedExecution(executor1, 1, "Test failure");

        uint256 newScore = reputationManager.getReputationScore(executor1);
        assertTrue(newScore < initialScore);

        IReputationManager.ReputationData memory data = reputationManager.getReputation(executor1);
        assertEq(data.streakCount, 0);
    }

    function test_StreakTracking() public {
        reputationManager.initializeReputation(executor1);

        // Build a streak
        for (uint256 i = 0; i < 10; i++) {
            reputationManager.recordSuccessfulExecution(executor1, i, 100000);
        }

        IReputationManager.ReputationData memory data = reputationManager.getReputation(executor1);
        assertEq(data.streakCount, 10);
        assertEq(data.longestStreak, 10);

        // Break the streak
        reputationManager.recordFailedExecution(executor1, 11, "Failure");

        data = reputationManager.getReputation(executor1);
        assertEq(data.streakCount, 0);
        assertEq(data.longestStreak, 10); // Longest streak preserved
    }

    function test_ApplyPenalty() public {
        reputationManager.initializeReputation(executor1);

        uint256 initialScore = reputationManager.getReputationScore(executor1);

        reputationManager.applyPenalty(executor1, 100, "Manual penalty");

        uint256 newScore = reputationManager.getReputationScore(executor1);
        assertTrue(newScore < initialScore);

        IReputationManager.ReputationData memory data = reputationManager.getReputation(executor1);
        assertEq(data.penaltyPoints, 100);
    }

    function test_CalculateTier() public {
        assertEq(uint8(reputationManager.calculateTier(50)), uint8(IReputationManager.ReputationTier.Novice));
        assertEq(uint8(reputationManager.calculateTier(200)), uint8(IReputationManager.ReputationTier.Bronze));
        assertEq(uint8(reputationManager.calculateTier(500)), uint8(IReputationManager.ReputationTier.Silver));
        assertEq(uint8(reputationManager.calculateTier(800)), uint8(IReputationManager.ReputationTier.Gold));
        assertEq(uint8(reputationManager.calculateTier(950)), uint8(IReputationManager.ReputationTier.Platinum));
    }

    function test_MeetsReputationThreshold() public {
        reputationManager.initializeReputation(executor1);

        assertTrue(reputationManager.meetsReputationThreshold(executor1, 400));
        assertTrue(reputationManager.meetsReputationThreshold(executor1, 500));
        assertFalse(reputationManager.meetsReputationThreshold(executor1, 600));
    }

    function test_TierChangesWithScore() public {
        reputationManager.initializeReputation(executor1);

        // Initial tier should be Silver (500 score)
        assertEq(uint8(reputationManager.getReputationTier(executor1)), uint8(IReputationManager.ReputationTier.Silver));

        // Build up score
        for (uint256 i = 0; i < 50; i++) {
            reputationManager.recordSuccessfulExecution(executor1, i, 100000);
        }

        // Should be higher tier now
        IReputationManager.ReputationTier tier = reputationManager.getReputationTier(executor1);
        assertTrue(uint8(tier) > uint8(IReputationManager.ReputationTier.Silver));
    }

    function test_GasEfficiencyBonus() public {
        reputationManager.initializeReputation(executor1);
        reputationManager.initializeReputation(executor2);

        uint256 initialScore1 = reputationManager.getReputationScore(executor1);
        uint256 initialScore2 = reputationManager.getReputationScore(executor2);

        // Low gas execution (gets bonus)
        reputationManager.recordSuccessfulExecution(executor1, 1, 100000);

        // High gas execution (no bonus)
        reputationManager.recordSuccessfulExecution(executor2, 2, 300000);

        uint256 score1 = reputationManager.getReputationScore(executor1);
        uint256 score2 = reputationManager.getReputationScore(executor2);

        // Both should increase, but executor1 should have higher score due to bonus
        assertTrue(score1 > initialScore1);
        assertTrue(score2 > initialScore2);
        assertTrue(score1 > score2);
    }

    function test_UninitializedExecutorReturnsDefault() public {
        // Uninitialized executor should return initial score
        assertEq(reputationManager.getReputationScore(executor1), 500);
        assertEq(uint8(reputationManager.getReputationTier(executor1)), uint8(IReputationManager.ReputationTier.Silver));
    }

    function test_SetBaseSuccessPoints() public {
        reputationManager.setBaseSuccessPoints(20);
        assertEq(reputationManager.baseSuccessPoints(), 20);
    }

    function test_SetBaseFailurePenalty() public {
        reputationManager.setBaseFailurePenalty(50);
        assertEq(reputationManager.baseFailurePenalty(), 50);
    }

    function test_SetGasEfficiencyBonus() public {
        reputationManager.setGasEfficiencyBonus(200);
        assertEq(reputationManager.gasEfficiencyBonus(), 200);
    }

    function test_SetStreakBonus() public {
        reputationManager.setStreakBonus(10);
        assertEq(reputationManager.streakBonus(), 10);
    }

    function test_OnlyAuthorizedCanRecord() public {
        reputationManager.initializeReputation(executor1);

        vm.prank(executor2);
        vm.expectRevert("ReputationManager: not authorized");
        reputationManager.recordSuccessfulExecution(executor1, 1, 100000);
    }

    function test_OnlyAuthorizedCanApplyPenalty() public {
        reputationManager.initializeReputation(executor1);

        vm.prank(executor2);
        vm.expectRevert("ReputationManager: not authorized");
        reputationManager.applyPenalty(executor1, 50, "Test");
    }
}
