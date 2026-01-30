// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/executor/ExecutorRegistry.sol";
import "../src/executor/ReputationManager.sol";
import "../src/executor/ExecutorSlasher.sol";
import "../src/executor/ExecutorStaking.sol";

/**
 * @title ExecutorIntegrationTest
 * @notice Integration tests for the complete executor staking and reputation system
 */
contract ExecutorIntegrationTest is Test {
    ExecutorRegistry public registry;
    ReputationManager public reputationManager;
    ExecutorSlasher public slasher;
    ExecutorStaking public staking;

    address public owner = address(this);
    address public executor1 = address(0x1001);
    address public executor2 = address(0x1002);
    address public executor3 = address(0x1003);

    uint256 public constant MIN_STAKE = 0.1 ether;
    uint256 public constant COOLDOWN = 7 days;

    function setUp() public {
        // Deploy all contracts
        registry = new ExecutorRegistry(MIN_STAKE, COOLDOWN);
        reputationManager = new ReputationManager(address(registry));
        slasher = new ExecutorSlasher(address(registry), address(reputationManager));
        staking = new ExecutorStaking(
            address(registry),
            address(reputationManager),
            address(slasher)
        );

        // Grant slasher role
        registry.grantSlasherRole(address(slasher));

        // Fund executors
        vm.deal(executor1, 10 ether);
        vm.deal(executor2, 10 ether);
        vm.deal(executor3, 10 ether);
    }

    // ============ Full Lifecycle Tests ============

    function test_ExecutorFullLifecycle() public {
        // 1. Register
        vm.prank(executor1);
        registry.register{value: 1 ether}();
        assertTrue(registry.isActive(executor1));

        // 2. Build reputation with successful executions
        for (uint8 i = 0; i < 10; i++) {
            vm.prank(address(registry));
            reputationManager.recordExecution(executor1, true, 50000, 100000);
        }

        (uint256 score,,,,,,) = reputationManager.reputationData(executor1);
        assertGt(score, 600); // Should have good score

        // 3. Experience a failure and slashing
        bytes32 flowId = keccak256("failedFlow");
        slasher.slashForFailedExecution(executor1, flowId);

        (uint256 stakedAmount,,,,,) = registry.executors(executor1);
        assertLt(stakedAmount, 1 ether); // Slashed

        // 4. Initiate withdrawal
        vm.prank(executor1);
        registry.initiateWithdrawal();

        // 5. Wait for cooldown
        vm.warp(block.timestamp + COOLDOWN + 1);

        // 6. Complete withdrawal
        uint256 balanceBefore = executor1.balance;
        vm.prank(executor1);
        registry.completeWithdrawal();

        assertGt(executor1.balance, balanceBefore);
    }

    function test_MultipleExecutorsCompetingForReputation() public {
        // Register all executors
        vm.prank(executor1);
        registry.register{value: 1 ether}();

        vm.prank(executor2);
        registry.register{value: 1 ether}();

        vm.prank(executor3);
        registry.register{value: 1 ether}();

        // Executor1: 20 successful executions
        for (uint8 i = 0; i < 20; i++) {
            vm.prank(address(registry));
            reputationManager.recordExecution(executor1, true, 40000, 100000);
        }

        // Executor2: 15 successful, 5 failed
        for (uint8 i = 0; i < 15; i++) {
            vm.prank(address(registry));
            reputationManager.recordExecution(executor2, true, 50000, 100000);
        }
        for (uint8 i = 0; i < 5; i++) {
            vm.prank(address(registry));
            reputationManager.recordExecution(executor2, false, 50000, 100000);
        }

        // Executor3: 10 successful with poor gas efficiency
        for (uint8 i = 0; i < 10; i++) {
            vm.prank(address(registry));
            reputationManager.recordExecution(executor3, true, 95000, 100000);
        }

        // Get scores
        (uint256 score1,,,,,,) = reputationManager.reputationData(executor1);
        (uint256 score2,,,,,,) = reputationManager.reputationData(executor2);
        (uint256 score3,,,,,,) = reputationManager.reputationData(executor3);

        // Executor1 should have highest score
        assertGt(score1, score2);
        assertGt(score1, score3);

        // Verify leaderboard
        (address[] memory topExecutors,) = reputationManager.getTopExecutors(3);
        assertEq(topExecutors[0], executor1);
    }

    function test_SlashingAndRecovery() public {
        vm.prank(executor1);
        registry.register{value: 5 ether}();

        // Build reputation
        for (uint8 i = 0; i < 10; i++) {
            vm.prank(address(registry));
            reputationManager.recordExecution(executor1, true, 50000, 100000);
        }

        uint256 initialStake;
        (initialStake,,,,,) = registry.executors(executor1);
        assertEq(initialStake, 5 ether);

        // Get slashed for timeout
        bytes32 flowId1 = keccak256("timeout1");
        slasher.slashForTimeout(executor1, flowId1);

        uint256 afterSlash;
        (afterSlash,,,,,) = registry.executors(executor1);
        assertEq(afterSlash, 4.9 ether); // 2% slashed

        // Add more stake to recover
        vm.prank(executor1);
        registry.addStake{value: 0.5 ether}();

        uint256 afterRecovery;
        (afterRecovery,,,,,) = registry.executors(executor1);
        assertEq(afterRecovery, 5.4 ether);
    }

    function test_SuspensionFromConsecutiveFailures() public {
        vm.prank(executor1);
        registry.register{value: 2 ether}();

        assertTrue(registry.isActive(executor1));

        // Three consecutive failures should suspend
        for (uint8 i = 0; i < 3; i++) {
            bytes32 flowId = keccak256(abi.encodePacked("fail", i));
            slasher.slashForFailedExecution(executor1, flowId);
        }

        assertFalse(registry.isActive(executor1));

        // Reactivate
        registry.reactivate(executor1);
        assertTrue(registry.isActive(executor1));
    }

    function test_MaliciousActivitySevereSlash() public {
        vm.prank(executor1);
        registry.register{value: 10 ether}();

        uint256 initialStake;
        (initialStake,,,,,) = registry.executors(executor1);
        assertEq(initialStake, 10 ether);

        // Slash for malicious activity
        slasher.slashForMaliciousActivity(executor1, "Attempted double execution");

        uint256 afterSlash;
        IExecutorRegistry.ExecutorStatus status;
        (afterSlash,,,status,,) = registry.executors(executor1);

        assertEq(afterSlash, 5 ether); // 50% slashed
        assertEq(uint256(status), uint256(IExecutorRegistry.ExecutorStatus.Suspended));
    }

    // ============ Tier Progression Integration Tests ============

    function test_TierProgressionThroughExecutions() public {
        vm.prank(executor1);
        registry.register{value: 1 ether}();

        // Initial tier should be Novice
        IReputationManager.ReputationTier tier = reputationManager.getTier(executor1);
        assertEq(uint256(tier), uint256(IReputationManager.ReputationTier.Novice));

        // Execute 50 successful transactions with good gas efficiency
        for (uint8 i = 0; i < 50; i++) {
            vm.prank(address(registry));
            reputationManager.recordExecution(executor1, true, 30000, 100000);
        }

        tier = reputationManager.getTier(executor1);
        // Should have progressed to at least Bronze/Silver
        assertGe(uint256(tier), uint256(IReputationManager.ReputationTier.Bronze));
    }

    function test_HighValueFlowEligibility() public {
        vm.prank(executor1);
        registry.register{value: 0.5 ether}();

        vm.prank(executor2);
        registry.register{value: 5 ether}();

        // Build reputation for both
        for (uint8 i = 0; i < 20; i++) {
            vm.prank(address(registry));
            reputationManager.recordExecution(executor1, true, 50000, 100000);

            vm.prank(address(registry));
            reputationManager.recordExecution(executor2, true, 50000, 100000);
        }

        // Executor2 with higher stake should be eligible for high-value flows
        bool eligible1 = staking.isEligibleForHighValueFlows(executor1);
        bool eligible2 = staking.isEligibleForHighValueFlows(executor2);

        // Executor2 should be eligible (higher stake)
        assertTrue(eligible2);
    }

    // ============ Withdrawal Flow Integration Tests ============

    function test_WithdrawalWithPendingReputation() public {
        vm.prank(executor1);
        registry.register{value: 2 ether}();

        // Build some reputation
        for (uint8 i = 0; i < 5; i++) {
            vm.prank(address(registry));
            reputationManager.recordExecution(executor1, true, 50000, 100000);
        }

        // Initiate withdrawal
        vm.prank(executor1);
        registry.initiateWithdrawal();

        // Reputation data should still be accessible
        (uint256 score, uint256 totalExecutions,,,,,) = reputationManager.reputationData(executor1);
        assertGt(score, 500);
        assertEq(totalExecutions, 5);

        // Wait and complete withdrawal
        vm.warp(block.timestamp + COOLDOWN + 1);

        vm.prank(executor1);
        registry.completeWithdrawal();

        // Reputation data persists
        (score, totalExecutions,,,,,) = reputationManager.reputationData(executor1);
        assertGt(score, 500);
        assertEq(totalExecutions, 5);
    }

    function test_ReregistrationAfterWithdrawal() public {
        vm.prank(executor1);
        registry.register{value: 1 ether}();

        // Build reputation
        for (uint8 i = 0; i < 10; i++) {
            vm.prank(address(registry));
            reputationManager.recordExecution(executor1, true, 50000, 100000);
        }

        // Withdraw
        vm.prank(executor1);
        registry.initiateWithdrawal();

        vm.warp(block.timestamp + COOLDOWN + 1);

        vm.prank(executor1);
        registry.completeWithdrawal();

        // Re-register with more stake
        vm.prank(executor1);
        registry.register{value: 2 ether}();

        assertTrue(registry.isActive(executor1));

        // Previous reputation should be maintained
        (uint256 score, uint256 totalExecutions,,,,,) = reputationManager.reputationData(executor1);
        assertGt(score, 500);
        assertEq(totalExecutions, 10);
    }

    // ============ Staking Facade Integration Tests ============

    function test_StakingFacadeEligibilityCheck() public {
        vm.prank(executor1);
        registry.register{value: 1 ether}();

        // Build good reputation
        for (uint8 i = 0; i < 20; i++) {
            vm.prank(address(registry));
            reputationManager.recordExecution(executor1, true, 40000, 100000);
        }

        assertTrue(staking.isEligible(executor1));

        // Suspend executor
        registry.suspend(executor1);

        assertFalse(staking.isEligible(executor1));
    }

    function test_StakingFacadeLeaderboard() public {
        // Register multiple executors
        vm.prank(executor1);
        registry.register{value: 1 ether}();

        vm.prank(executor2);
        registry.register{value: 1 ether}();

        vm.prank(executor3);
        registry.register{value: 1 ether}();

        // Build varying reputations
        for (uint8 i = 0; i < 30; i++) {
            vm.prank(address(registry));
            reputationManager.recordExecution(executor1, true, 30000, 100000);
        }

        for (uint8 i = 0; i < 20; i++) {
            vm.prank(address(registry));
            reputationManager.recordExecution(executor2, true, 50000, 100000);
        }

        for (uint8 i = 0; i < 10; i++) {
            vm.prank(address(registry));
            reputationManager.recordExecution(executor3, true, 70000, 100000);
        }

        (address[] memory topExecutors, uint256[] memory scores) = staking.getLeaderboard(3);

        assertEq(topExecutors.length, 3);
        assertEq(topExecutors[0], executor1); // Highest score
        assertGt(scores[0], scores[1]);
        assertGt(scores[1], scores[2]);
    }

    // ============ Edge Cases ============

    function test_SlashingDuringWithdrawalCooldown() public {
        vm.prank(executor1);
        registry.register{value: 2 ether}();

        // Initiate withdrawal
        vm.prank(executor1);
        registry.initiateWithdrawal();

        // Get slashed during cooldown
        bytes32 flowId = keccak256("lateSlash");
        slasher.slashForFailedExecution(executor1, flowId);

        // Wait for cooldown
        vm.warp(block.timestamp + COOLDOWN + 1);

        // Complete withdrawal - should get slashed amount
        uint256 balanceBefore = executor1.balance;
        vm.prank(executor1);
        registry.completeWithdrawal();

        uint256 received = executor1.balance - balanceBefore;
        assertLt(received, 2 ether); // Received less due to slash
    }

    function test_MultipleSlashTypesAccumulate() public {
        vm.prank(executor1);
        registry.register{value: 10 ether}();

        uint256 currentStake = 10 ether;

        // Failed execution: 1%
        bytes32 flowId1 = keccak256("fail1");
        slasher.slashForFailedExecution(executor1, flowId1);
        currentStake -= (10 ether * 1) / 100; // -0.1 ether

        // Timeout: 2%
        bytes32 flowId2 = keccak256("timeout1");
        slasher.slashForTimeout(executor1, flowId2);
        currentStake -= (currentStake * 2) / 100;

        (uint256 stakedAmount,,,,,) = registry.executors(executor1);
        assertEq(stakedAmount, currentStake);
    }
}
