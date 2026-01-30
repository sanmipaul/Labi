// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/executor/ReputationManager.sol";

contract ReputationManagerFuzzTest is Test {
    ReputationManager public reputationManager;

    address public owner = address(this);
    address public registry = address(0x1);

    function setUp() public {
        reputationManager = new ReputationManager(registry);
    }

    // ============ Score Recording Fuzz Tests ============

    function testFuzz_RecordSuccessfulExecution(uint256 gasUsed, uint256 gasLimit) public {
        gasUsed = bound(gasUsed, 21000, 10_000_000);
        gasLimit = bound(gasLimit, gasUsed, 30_000_000);

        address executor = makeAddr("executor");

        vm.prank(registry);
        reputationManager.recordExecution(executor, true, gasUsed, gasLimit);

        (
            uint256 score,
            uint256 totalExecutions,
            uint256 successfulExecutions,
            uint256 currentStreak,
            ,
            ,
        ) = reputationManager.reputationData(executor);

        assertGt(score, 500); // Should increase from base
        assertEq(totalExecutions, 1);
        assertEq(successfulExecutions, 1);
        assertEq(currentStreak, 1);
    }

    function testFuzz_RecordFailedExecution(uint256 gasUsed, uint256 gasLimit) public {
        gasUsed = bound(gasUsed, 21000, 10_000_000);
        gasLimit = bound(gasLimit, gasUsed, 30_000_000);

        address executor = makeAddr("executor");

        // First record a success to establish baseline
        vm.prank(registry);
        reputationManager.recordExecution(executor, true, gasUsed, gasLimit);

        uint256 scoreAfterSuccess;
        (scoreAfterSuccess,,,,,,) = reputationManager.reputationData(executor);

        // Record a failure
        vm.prank(registry);
        reputationManager.recordExecution(executor, false, gasUsed, gasLimit);

        (
            uint256 score,
            uint256 totalExecutions,
            uint256 successfulExecutions,
            uint256 currentStreak,
            ,
            ,
        ) = reputationManager.reputationData(executor);

        assertLt(score, scoreAfterSuccess); // Should decrease
        assertEq(totalExecutions, 2);
        assertEq(successfulExecutions, 1);
        assertEq(currentStreak, 0); // Streak reset
    }

    function testFuzz_MultipleSuccessfulExecutions(uint8 executionCount) public {
        executionCount = uint8(bound(executionCount, 1, 100));

        address executor = makeAddr("executor");

        for (uint8 i = 0; i < executionCount; i++) {
            vm.prank(registry);
            reputationManager.recordExecution(executor, true, 50000, 100000);
        }

        (
            uint256 score,
            uint256 totalExecutions,
            uint256 successfulExecutions,
            uint256 currentStreak,
            ,
            ,
        ) = reputationManager.reputationData(executor);

        assertEq(totalExecutions, executionCount);
        assertEq(successfulExecutions, executionCount);
        assertEq(currentStreak, executionCount);
        assertLe(score, 1000); // Score capped at 1000
    }

    // ============ Gas Efficiency Fuzz Tests ============

    function testFuzz_GasEfficiencyBonus(uint256 gasUsed, uint256 gasLimit) public {
        gasLimit = bound(gasLimit, 100000, 10_000_000);
        // Good efficiency: use 30-70% of gas limit
        gasUsed = bound(gasUsed, gasLimit * 30 / 100, gasLimit * 70 / 100);

        address executor = makeAddr("executor");

        vm.prank(registry);
        reputationManager.recordExecution(executor, true, gasUsed, gasLimit);

        (uint256 score,,,,,,) = reputationManager.reputationData(executor);

        // With good gas efficiency, score should get bonus
        assertGt(score, 500);
    }

    function testFuzz_PoorGasEfficiency(uint256 gasLimit) public {
        gasLimit = bound(gasLimit, 100000, 10_000_000);
        // Poor efficiency: use 95%+ of gas limit
        uint256 gasUsed = gasLimit * 95 / 100;

        address executor = makeAddr("executor");

        vm.prank(registry);
        reputationManager.recordExecution(executor, true, gasUsed, gasLimit);

        address executor2 = makeAddr("executor2");

        // Compare with better efficiency
        vm.prank(registry);
        reputationManager.recordExecution(executor2, true, gasLimit * 50 / 100, gasLimit);

        (uint256 score1,,,,,,) = reputationManager.reputationData(executor);
        (uint256 score2,,,,,,) = reputationManager.reputationData(executor2);

        // Better efficiency should yield better score
        assertLe(score1, score2);
    }

    // ============ Streak Fuzz Tests ============

    function testFuzz_StreakBuilding(uint8 streakLength) public {
        streakLength = uint8(bound(streakLength, 1, 50));

        address executor = makeAddr("executor");

        for (uint8 i = 0; i < streakLength; i++) {
            vm.prank(registry);
            reputationManager.recordExecution(executor, true, 50000, 100000);
        }

        (,,,uint256 currentStreak,uint256 bestStreak,,) = reputationManager.reputationData(executor);

        assertEq(currentStreak, streakLength);
        assertEq(bestStreak, streakLength);
    }

    function testFuzz_StreakResetOnFailure(uint8 streakBefore, uint8 streakAfter) public {
        streakBefore = uint8(bound(streakBefore, 1, 20));
        streakAfter = uint8(bound(streakAfter, 1, 20));

        address executor = makeAddr("executor");

        // Build initial streak
        for (uint8 i = 0; i < streakBefore; i++) {
            vm.prank(registry);
            reputationManager.recordExecution(executor, true, 50000, 100000);
        }

        // Fail once
        vm.prank(registry);
        reputationManager.recordExecution(executor, false, 50000, 100000);

        // Build new streak
        for (uint8 i = 0; i < streakAfter; i++) {
            vm.prank(registry);
            reputationManager.recordExecution(executor, true, 50000, 100000);
        }

        (,,,uint256 currentStreak, uint256 bestStreak,,) = reputationManager.reputationData(executor);

        assertEq(currentStreak, streakAfter);
        assertEq(bestStreak, streakBefore > streakAfter ? streakBefore : streakAfter);
    }

    // ============ Tier Fuzz Tests ============

    function testFuzz_TierProgression(uint8 successCount) public {
        successCount = uint8(bound(successCount, 1, 200));

        address executor = makeAddr("executor");

        for (uint8 i = 0; i < successCount; i++) {
            vm.prank(registry);
            reputationManager.recordExecution(executor, true, 30000, 100000);
        }

        IReputationManager.ReputationTier tier = reputationManager.getTier(executor);
        (uint256 score,,,,,,) = reputationManager.reputationData(executor);

        // Verify tier matches score
        if (score >= 900) {
            assertEq(uint256(tier), uint256(IReputationManager.ReputationTier.Platinum));
        } else if (score >= 750) {
            assertEq(uint256(tier), uint256(IReputationManager.ReputationTier.Gold));
        } else if (score >= 600) {
            assertEq(uint256(tier), uint256(IReputationManager.ReputationTier.Silver));
        } else if (score >= 400) {
            assertEq(uint256(tier), uint256(IReputationManager.ReputationTier.Bronze));
        } else {
            assertEq(uint256(tier), uint256(IReputationManager.ReputationTier.Novice));
        }
    }

    // ============ Score Bounds Fuzz Tests ============

    function testFuzz_ScoreNeverExceeds1000(uint16 successCount) public {
        successCount = uint16(bound(successCount, 1, 500));

        address executor = makeAddr("executor");

        for (uint16 i = 0; i < successCount; i++) {
            vm.prank(registry);
            reputationManager.recordExecution(executor, true, 20000, 100000);
        }

        (uint256 score,,,,,,) = reputationManager.reputationData(executor);
        assertLe(score, 1000);
    }

    function testFuzz_ScoreNeverBelowZero(uint8 failCount) public {
        failCount = uint8(bound(failCount, 1, 100));

        address executor = makeAddr("executor");

        // First success to initialize
        vm.prank(registry);
        reputationManager.recordExecution(executor, true, 50000, 100000);

        // Multiple failures
        for (uint8 i = 0; i < failCount; i++) {
            vm.prank(registry);
            reputationManager.recordExecution(executor, false, 50000, 100000);
        }

        (uint256 score,,,,,,) = reputationManager.reputationData(executor);
        assertGe(score, 0); // Score should never underflow
    }

    // ============ Multiple Executors Fuzz Tests ============

    function testFuzz_MultipleExecutorsIndependentScores(uint8 executorCount) public {
        executorCount = uint8(bound(executorCount, 2, 30));

        for (uint8 i = 0; i < executorCount; i++) {
            address executor = address(uint160(3000 + i));
            uint256 successCount = (i % 10) + 1;

            for (uint256 j = 0; j < successCount; j++) {
                vm.prank(registry);
                reputationManager.recordExecution(executor, true, 50000, 100000);
            }
        }

        // Verify scores are independent
        for (uint8 i = 0; i < executorCount; i++) {
            address executor = address(uint160(3000 + i));
            (,uint256 totalExecutions,,,,,) = reputationManager.reputationData(executor);
            assertEq(totalExecutions, (i % 10) + 1);
        }
    }

    function testFuzz_LeaderboardOrdering(uint8 executorCount) public {
        executorCount = uint8(bound(executorCount, 2, 20));

        // Give each executor different number of successes
        for (uint8 i = 0; i < executorCount; i++) {
            address executor = address(uint160(4000 + i));
            uint256 successCount = i + 1;

            for (uint256 j = 0; j < successCount; j++) {
                vm.prank(registry);
                reputationManager.recordExecution(executor, true, 50000, 100000);
            }
        }

        (address[] memory topExecutors, uint256[] memory scores) = reputationManager.getTopExecutors(executorCount);

        // Verify ordering is descending
        for (uint256 i = 1; i < topExecutors.length; i++) {
            assertGe(scores[i - 1], scores[i]);
        }
    }

    // ============ Timestamp Fuzz Tests ============

    function testFuzz_LastExecutionTimestamp(uint256 timestamp) public {
        timestamp = bound(timestamp, 1, type(uint64).max);
        vm.warp(timestamp);

        address executor = makeAddr("executor");

        vm.prank(registry);
        reputationManager.recordExecution(executor, true, 50000, 100000);

        (,,,,, uint256 lastExecution,) = reputationManager.reputationData(executor);
        assertEq(lastExecution, timestamp);
    }

    function testFuzz_ConsecutiveFailureTracking(uint8 failCount) public {
        failCount = uint8(bound(failCount, 1, 20));

        address executor = makeAddr("executor");

        // First success
        vm.prank(registry);
        reputationManager.recordExecution(executor, true, 50000, 100000);

        // Multiple failures
        for (uint8 i = 0; i < failCount; i++) {
            vm.prank(registry);
            reputationManager.recordExecution(executor, false, 50000, 100000);
        }

        (,,,,,, uint256 consecutiveFailures) = reputationManager.reputationData(executor);
        assertEq(consecutiveFailures, failCount);
    }
}
