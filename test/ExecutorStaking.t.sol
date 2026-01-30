// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/executor/ExecutorRegistry.sol";
import "../src/executor/ReputationManager.sol";
import "../src/executor/ExecutorStaking.sol";

contract ExecutorStakingTest is Test {
    ExecutorRegistry public registry;
    ReputationManager public reputationManager;
    ExecutorStaking public staking;

    address public owner;
    address public executor1;
    address public executor2;
    address public treasury;

    uint256 constant MINIMUM_STAKE = 1 ether;
    uint256 constant WITHDRAWAL_COOLDOWN = 7 days;

    function setUp() public {
        owner = address(this);
        executor1 = makeAddr("executor1");
        executor2 = makeAddr("executor2");
        treasury = makeAddr("treasury");

        registry = new ExecutorRegistry(MINIMUM_STAKE, WITHDRAWAL_COOLDOWN, treasury);
        reputationManager = new ReputationManager();
        staking = new ExecutorStaking(address(registry), address(reputationManager));

        // Setup authorizations
        reputationManager.setAuthorizedCaller(address(this), true);

        // Fund executors
        vm.deal(executor1, 10 ether);
        vm.deal(executor2, 10 ether);

        // Register executor1 with high stake
        vm.prank(executor1);
        registry.registerExecutor{value: 3 ether}();

        // Register executor2 with minimum stake
        vm.prank(executor2);
        registry.registerExecutor{value: 1 ether}();

        // Initialize reputations
        reputationManager.initializeReputation(executor1);
        reputationManager.initializeReputation(executor2);
    }

    function test_CheckEligibilityActiveExecutor() public {
        (bool isEligible, string memory reason) = staking.checkEligibility(executor1, 1 ether);

        assertTrue(isEligible);
        assertEq(reason, "Eligible");
    }

    function test_CheckEligibilityInactiveExecutor() public {
        registry.suspendExecutor(executor1, "Test suspension");

        (bool isEligible, string memory reason) = staking.checkEligibility(executor1, 1 ether);

        assertFalse(isEligible);
        assertEq(reason, "Executor is not active");
    }

    function test_CheckEligibilityHighValueFlow() public {
        // executor1 has 3 ether stake (meets 2 ether requirement)
        // Build up reputation to meet 600 threshold
        for (uint256 i = 0; i < 15; i++) {
            reputationManager.recordSuccessfulExecution(executor1, i, 100000);
        }

        (bool isEligible, ) = staking.checkEligibility(executor1, 15 ether);

        assertTrue(isEligible);
    }

    function test_CheckEligibilityHighValueFlowInsufficientReputation() public {
        // executor1 has only 500 reputation (initial), needs 600
        (bool isEligible, string memory reason) = staking.checkEligibility(executor1, 15 ether);

        assertFalse(isEligible);
        assertEq(reason, "Insufficient reputation for high-value flow");
    }

    function test_CheckEligibilityHighValueFlowInsufficientStake() public {
        // executor2 has only 1 ether stake, needs 2 ether for high-value
        // First boost reputation
        for (uint256 i = 0; i < 15; i++) {
            reputationManager.recordSuccessfulExecution(executor2, i, 100000);
        }

        (bool isEligible, string memory reason) = staking.checkEligibility(executor2, 15 ether);

        assertFalse(isEligible);
        assertEq(reason, "Insufficient stake for high-value flow");
    }

    function test_GetExecutorStatus() public {
        // Record some executions
        registry.setAuthorizedCaller(address(this), true);
        registry.recordExecution(executor1, 1, true);
        registry.recordExecution(executor1, 2, true);
        registry.recordExecution(executor1, 3, false);

        reputationManager.recordSuccessfulExecution(executor1, 1, 100000);
        reputationManager.recordSuccessfulExecution(executor1, 2, 100000);

        (
            bool isActive,
            uint256 stakedAmount,
            uint256 reputationScore,
            IReputationManager.ReputationTier tier,
            uint256 totalExecutions,
            uint256 successRate
        ) = staking.getExecutorStatus(executor1);

        assertTrue(isActive);
        assertEq(stakedAmount, 3 ether);
        assertTrue(reputationScore >= 500);
        assertEq(totalExecutions, 3);
        assertEq(successRate, 6666); // 66.66% (2/3)
    }

    function test_GetLeaderboardData() public {
        reputationManager.recordSuccessfulExecution(executor1, 1, 100000);
        reputationManager.recordSuccessfulExecution(executor1, 2, 100000);
        reputationManager.recordSuccessfulExecution(executor1, 3, 100000);

        registry.setAuthorizedCaller(address(this), true);
        registry.recordExecution(executor1, 1, true);
        registry.recordExecution(executor1, 2, true);
        registry.recordExecution(executor1, 3, true);

        (uint256 score, uint256 successRate, uint256 totalExecutions, uint256 streak) = staking.getLeaderboardData(executor1);

        assertTrue(score > 500);
        assertEq(successRate, 10000); // 100%
        assertEq(totalExecutions, 3);
        assertEq(streak, 3);
    }

    function test_CalculatePotentialReward() public {
        uint256 baseReward = 0.1 ether;

        // Silver tier (500 score) - 10% bonus
        uint256 reward = staking.calculatePotentialReward(executor1, baseReward);
        uint256 expectedMinReward = baseReward + (baseReward * 1000 / 10000); // At least silver bonus

        assertTrue(reward >= expectedMinReward);
    }

    function test_CalculatePotentialRewardWithStreak() public {
        // Build streak
        for (uint256 i = 0; i < 5; i++) {
            reputationManager.recordSuccessfulExecution(executor1, i, 100000);
        }

        uint256 baseReward = 0.1 ether;
        uint256 rewardWithStreak = staking.calculatePotentialReward(executor1, baseReward);
        uint256 baseRewardOnly = baseReward + (baseReward * 1000 / 10000); // Silver bonus only

        // Should have streak bonus
        assertTrue(rewardWithStreak > baseRewardOnly);
    }

    function test_MeetsTierRequirement() public {
        // Initial tier is Silver (500 score)
        assertTrue(staking.meetssTierRequirement(executor1, IReputationManager.ReputationTier.Novice));
        assertTrue(staking.meetssTierRequirement(executor1, IReputationManager.ReputationTier.Bronze));
        assertTrue(staking.meetssTierRequirement(executor1, IReputationManager.ReputationTier.Silver));
        assertFalse(staking.meetssTierRequirement(executor1, IReputationManager.ReputationTier.Gold));
        assertFalse(staking.meetssTierRequirement(executor1, IReputationManager.ReputationTier.Platinum));
    }

    function test_SetMinReputationForHighValue() public {
        staking.setMinReputationForHighValue(700);
        assertEq(staking.minReputationForHighValue(), 700);
    }

    function test_SetMinStakeForHighValue() public {
        staking.setMinStakeForHighValue(5 ether);
        assertEq(staking.minStakeForHighValue(), 5 ether);
    }

    function test_SetHighValueThreshold() public {
        staking.setHighValueThreshold(20 ether);
        assertEq(staking.highValueThreshold(), 20 ether);
    }

    function test_OnlyOwnerCanSetParameters() public {
        vm.prank(executor1);
        vm.expectRevert("ExecutorStaking: caller is not owner");
        staking.setMinReputationForHighValue(700);

        vm.prank(executor1);
        vm.expectRevert("ExecutorStaking: caller is not owner");
        staking.setMinStakeForHighValue(5 ether);
    }
}
