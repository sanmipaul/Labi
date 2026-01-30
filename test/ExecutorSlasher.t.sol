// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/executor/ExecutorRegistry.sol";
import "../src/executor/ReputationManager.sol";
import "../src/executor/ExecutorSlasher.sol";

contract ExecutorSlasherTest is Test {
    ExecutorRegistry public registry;
    ReputationManager public reputationManager;
    ExecutorSlasher public slasher;

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
        slasher = new ExecutorSlasher(address(registry), address(reputationManager));

        // Setup authorizations
        registry.setAuthorizedCaller(address(slasher), true);
        reputationManager.setAuthorizedCaller(address(slasher), true);
        slasher.setAuthorizedSlasher(address(this), true);

        // Fund executors
        vm.deal(executor1, 10 ether);
        vm.deal(executor2, 10 ether);

        // Register executors
        vm.prank(executor1);
        registry.registerExecutor{value: 2 ether}();

        vm.prank(executor2);
        registry.registerExecutor{value: 2 ether}();

        // Initialize reputation
        reputationManager.setAuthorizedCaller(address(this), true);
        reputationManager.initializeReputation(executor1);
        reputationManager.initializeReputation(executor2);
    }

    function test_SlashForFailedExecution() public {
        uint256 stakeBeforeSlash = registry.getStakedAmount(executor1);
        uint256 expectedSlash = (stakeBeforeSlash * 100) / 10000; // 1%

        slasher.slashForFailedExecution(executor1, 1);

        uint256 stakeAfterSlash = registry.getStakedAmount(executor1);
        assertEq(stakeBeforeSlash - stakeAfterSlash, expectedSlash);
    }

    function test_SlashForFailedExecutionIncrementsFailures() public {
        assertEq(slasher.getConsecutiveFailures(executor1), 0);

        slasher.slashForFailedExecution(executor1, 1);
        assertEq(slasher.getConsecutiveFailures(executor1), 1);

        slasher.slashForFailedExecution(executor1, 2);
        assertEq(slasher.getConsecutiveFailures(executor1), 2);
    }

    function test_AutoSuspensionAfterConsecutiveFailures() public {
        // Slash 5 times (default threshold)
        for (uint256 i = 0; i < 5; i++) {
            slasher.slashForFailedExecution(executor1, i);
        }

        // Executor should be suspended
        assertFalse(registry.isActiveExecutor(executor1));
    }

    function test_SlashForMaliciousBehavior() public {
        uint256 stakeBeforeSlash = registry.getStakedAmount(executor1);
        uint256 expectedSlash = (stakeBeforeSlash * 5000) / 10000; // 50%

        slasher.slashForMaliciousBehavior(executor1, "Malicious action detected");

        uint256 stakeAfterSlash = registry.getStakedAmount(executor1);
        assertEq(stakeBeforeSlash - stakeAfterSlash, expectedSlash);

        // Should also be suspended
        assertFalse(registry.isActiveExecutor(executor1));
    }

    function test_SlashForTimeout() public {
        uint256 stakeBeforeSlash = registry.getStakedAmount(executor1);
        uint256 expectedSlash = (stakeBeforeSlash * 200) / 10000; // 2%

        slasher.slashForTimeout(executor1, 1);

        uint256 stakeAfterSlash = registry.getStakedAmount(executor1);
        assertEq(stakeBeforeSlash - stakeAfterSlash, expectedSlash);
    }

    function test_ManualSlash() public {
        uint256 slashAmount = 0.5 ether;
        uint256 reputationPenalty = 100;

        uint256 stakeBeforeSlash = registry.getStakedAmount(executor1);
        uint256 scoreBeforeSlash = reputationManager.getReputationScore(executor1);

        slasher.manualSlash(executor1, slashAmount, reputationPenalty, "Manual slash");

        uint256 stakeAfterSlash = registry.getStakedAmount(executor1);
        uint256 scoreAfterSlash = reputationManager.getReputationScore(executor1);

        assertEq(stakeBeforeSlash - stakeAfterSlash, slashAmount);
        assertTrue(scoreAfterSlash < scoreBeforeSlash);
    }

    function test_ResetConsecutiveFailures() public {
        slasher.slashForFailedExecution(executor1, 1);
        slasher.slashForFailedExecution(executor1, 2);
        assertEq(slasher.getConsecutiveFailures(executor1), 2);

        slasher.resetConsecutiveFailures(executor1);
        assertEq(slasher.getConsecutiveFailures(executor1), 0);
    }

    function test_CalculateSlashAmount() public {
        uint256 staked = registry.getStakedAmount(executor1);

        uint256 failedSlash = slasher.calculateSlashAmount(executor1, ExecutorSlasher.SlashReason.FailedExecution);
        assertEq(failedSlash, (staked * 100) / 10000);

        uint256 maliciousSlash = slasher.calculateSlashAmount(executor1, ExecutorSlasher.SlashReason.MaliciousBehavior);
        assertEq(maliciousSlash, (staked * 5000) / 10000);

        uint256 timeoutSlash = slasher.calculateSlashAmount(executor1, ExecutorSlasher.SlashReason.Timeout);
        assertEq(timeoutSlash, (staked * 200) / 10000);
    }

    function test_ReputationPenaltyOnSlash() public {
        uint256 scoreBefore = reputationManager.getReputationScore(executor1);

        slasher.slashForFailedExecution(executor1, 1);

        uint256 scoreAfter = reputationManager.getReputationScore(executor1);
        assertTrue(scoreAfter < scoreBefore);
    }

    function test_OnlyOwnerCanSlashForMalicious() public {
        vm.prank(executor2);
        vm.expectRevert("ExecutorSlasher: caller is not owner");
        slasher.slashForMaliciousBehavior(executor1, "Test");
    }

    function test_OnlyOwnerCanManualSlash() public {
        vm.prank(executor2);
        vm.expectRevert("ExecutorSlasher: caller is not owner");
        slasher.manualSlash(executor1, 0.1 ether, 50, "Test");
    }

    function test_SetFailedExecutionSlashBps() public {
        slasher.setFailedExecutionSlashBps(200);
        assertEq(slasher.failedExecutionSlashBps(), 200);
    }

    function test_SetMaliciousSlashBps() public {
        slasher.setMaliciousSlashBps(7500);
        assertEq(slasher.maliciousSlashBps(), 7500);
    }

    function test_SetTimeoutSlashBps() public {
        slasher.setTimeoutSlashBps(300);
        assertEq(slasher.timeoutSlashBps(), 300);
    }

    function test_SetReputationPenalties() public {
        slasher.setReputationPenalties(100, 600, 150);
        assertEq(slasher.failedExecutionPenalty(), 100);
        assertEq(slasher.maliciousPenalty(), 600);
        assertEq(slasher.timeoutPenalty(), 150);
    }

    function test_SetConsecutiveFailureThreshold() public {
        slasher.setConsecutiveFailureThreshold(10);
        assertEq(slasher.consecutiveFailureThreshold(), 10);
    }

    function test_RevertInvalidSlashBps() public {
        vm.expectRevert("ExecutorSlasher: invalid bps");
        slasher.setFailedExecutionSlashBps(10001);

        vm.expectRevert("ExecutorSlasher: invalid bps");
        slasher.setMaliciousSlashBps(10001);

        vm.expectRevert("ExecutorSlasher: invalid bps");
        slasher.setTimeoutSlashBps(10001);
    }
}
