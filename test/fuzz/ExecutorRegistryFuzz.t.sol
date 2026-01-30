// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/executor/ExecutorRegistry.sol";

contract ExecutorRegistryFuzzTest is Test {
    ExecutorRegistry public registry;

    address public owner = address(this);
    uint256 public constant MIN_STAKE = 0.1 ether;
    uint256 public constant COOLDOWN = 7 days;

    function setUp() public {
        registry = new ExecutorRegistry(MIN_STAKE, COOLDOWN);
    }

    // ============ Registration Fuzz Tests ============

    function testFuzz_RegisterWithVariousStakes(uint256 stake) public {
        stake = bound(stake, MIN_STAKE, 1000 ether);

        address executor = makeAddr("executor");
        vm.deal(executor, stake);

        vm.prank(executor);
        registry.register{value: stake}();

        (
            uint256 stakedAmount,
            ,
            ,
            IExecutorRegistry.ExecutorStatus status,
            ,
        ) = registry.executors(executor);

        assertEq(stakedAmount, stake);
        assertEq(uint256(status), uint256(IExecutorRegistry.ExecutorStatus.Active));
    }

    function testFuzz_RegisterInsufficientStake(uint256 stake) public {
        stake = bound(stake, 0, MIN_STAKE - 1);

        address executor = makeAddr("executor");
        vm.deal(executor, stake);

        vm.prank(executor);
        vm.expectRevert("Insufficient stake");
        registry.register{value: stake}();
    }

    function testFuzz_AddStakeVariousAmounts(uint256 initialStake, uint256 additionalStake) public {
        initialStake = bound(initialStake, MIN_STAKE, 100 ether);
        additionalStake = bound(additionalStake, 0.001 ether, 100 ether);

        address executor = makeAddr("executor");
        vm.deal(executor, initialStake + additionalStake);

        vm.startPrank(executor);
        registry.register{value: initialStake}();
        registry.addStake{value: additionalStake}();
        vm.stopPrank();

        (uint256 stakedAmount,,,,,) = registry.executors(executor);
        assertEq(stakedAmount, initialStake + additionalStake);
    }

    // ============ Withdrawal Fuzz Tests ============

    function testFuzz_WithdrawAfterCooldown(uint256 stake, uint256 cooldownExtra) public {
        stake = bound(stake, MIN_STAKE, 100 ether);
        cooldownExtra = bound(cooldownExtra, 0, 30 days);

        address executor = makeAddr("executor");
        vm.deal(executor, stake);

        vm.prank(executor);
        registry.register{value: stake}();

        vm.prank(executor);
        registry.initiateWithdrawal();

        // Wait for cooldown plus extra time
        vm.warp(block.timestamp + COOLDOWN + cooldownExtra);

        uint256 balanceBefore = executor.balance;

        vm.prank(executor);
        registry.completeWithdrawal();

        assertEq(executor.balance, balanceBefore + stake);
    }

    function testFuzz_WithdrawBeforeCooldown(uint256 stake, uint256 timeElapsed) public {
        stake = bound(stake, MIN_STAKE, 100 ether);
        timeElapsed = bound(timeElapsed, 0, COOLDOWN - 1);

        address executor = makeAddr("executor");
        vm.deal(executor, stake);

        vm.prank(executor);
        registry.register{value: stake}();

        vm.prank(executor);
        registry.initiateWithdrawal();

        vm.warp(block.timestamp + timeElapsed);

        vm.prank(executor);
        vm.expectRevert("Cooldown not elapsed");
        registry.completeWithdrawal();
    }

    // ============ Slashing Fuzz Tests ============

    function testFuzz_SlashVariousAmounts(uint256 stake, uint256 slashPercent) public {
        stake = bound(stake, MIN_STAKE, 100 ether);
        slashPercent = bound(slashPercent, 1, 100);

        address executor = makeAddr("executor");
        vm.deal(executor, stake);

        vm.prank(executor);
        registry.register{value: stake}();

        uint256 slashAmount = (stake * slashPercent) / 100;
        if (slashAmount == 0) slashAmount = 1;
        if (slashAmount > stake) slashAmount = stake;

        registry.slash(executor, slashAmount);

        (uint256 stakedAmount,,,,,) = registry.executors(executor);
        assertEq(stakedAmount, stake - slashAmount);
    }

    function testFuzz_SlashBelowMinimum(uint256 stake) public {
        stake = bound(stake, MIN_STAKE, MIN_STAKE + 0.05 ether);

        address executor = makeAddr("executor");
        vm.deal(executor, stake);

        vm.prank(executor);
        registry.register{value: stake}();

        // Slash amount that brings stake below minimum
        uint256 slashAmount = stake - MIN_STAKE + 0.01 ether;
        if (slashAmount <= stake) {
            registry.slash(executor, slashAmount);

            (
                uint256 stakedAmount,
                ,
                ,
                IExecutorRegistry.ExecutorStatus status,
                ,
            ) = registry.executors(executor);

            assertEq(stakedAmount, stake - slashAmount);
            // Should be suspended due to below minimum stake
            assertEq(uint256(status), uint256(IExecutorRegistry.ExecutorStatus.Suspended));
        }
    }

    // ============ Multiple Executors Fuzz Tests ============

    function testFuzz_MultipleExecutorsRegistration(uint8 executorCount) public {
        executorCount = uint8(bound(executorCount, 1, 50));

        for (uint8 i = 0; i < executorCount; i++) {
            address executor = address(uint160(1000 + i));
            uint256 stake = MIN_STAKE + (uint256(i) * 0.01 ether);
            vm.deal(executor, stake);

            vm.prank(executor);
            registry.register{value: stake}();
        }

        // Verify all registered
        for (uint8 i = 0; i < executorCount; i++) {
            address executor = address(uint160(1000 + i));
            assertTrue(registry.isActive(executor));
        }
    }

    function testFuzz_GetActiveExecutorsAfterSuspensions(uint8 totalCount, uint8 suspendCount) public {
        totalCount = uint8(bound(totalCount, 5, 20));
        suspendCount = uint8(bound(suspendCount, 0, totalCount - 1));

        // Register executors
        for (uint8 i = 0; i < totalCount; i++) {
            address executor = address(uint160(2000 + i));
            vm.deal(executor, MIN_STAKE);

            vm.prank(executor);
            registry.register{value: MIN_STAKE}();
        }

        // Suspend some
        for (uint8 i = 0; i < suspendCount; i++) {
            address executor = address(uint160(2000 + i));
            registry.suspend(executor);
        }

        address[] memory activeExecutors = registry.getActiveExecutors();
        assertEq(activeExecutors.length, totalCount - suspendCount);
    }

    // ============ Timestamp Fuzz Tests ============

    function testFuzz_RegistrationTimestamp(uint256 timestamp) public {
        timestamp = bound(timestamp, 1, type(uint64).max);
        vm.warp(timestamp);

        address executor = makeAddr("executor");
        vm.deal(executor, MIN_STAKE);

        vm.prank(executor);
        registry.register{value: MIN_STAKE}();

        (, uint256 registeredAt,,,,) = registry.executors(executor);
        assertEq(registeredAt, timestamp);
    }

    function testFuzz_WithdrawalTimestampTracking(uint256 startTime, uint256 withdrawalDelay) public {
        startTime = bound(startTime, 1, type(uint64).max - 30 days);
        withdrawalDelay = bound(withdrawalDelay, 0, 30 days);

        vm.warp(startTime);

        address executor = makeAddr("executor");
        vm.deal(executor, MIN_STAKE);

        vm.prank(executor);
        registry.register{value: MIN_STAKE}();

        vm.warp(startTime + withdrawalDelay);

        vm.prank(executor);
        registry.initiateWithdrawal();

        (,,uint256 withdrawalInitiated,,,) = registry.executors(executor);
        assertEq(withdrawalInitiated, startTime + withdrawalDelay);
    }

    // ============ Boundary Tests ============

    function testFuzz_ExactMinimumStake() public {
        address executor = makeAddr("executor");
        vm.deal(executor, MIN_STAKE);

        vm.prank(executor);
        registry.register{value: MIN_STAKE}();

        assertTrue(registry.isActive(executor));
    }

    function testFuzz_MaxStakeAmount(uint256 stake) public {
        stake = bound(stake, 100 ether, 10000 ether);

        address executor = makeAddr("executor");
        vm.deal(executor, stake);

        vm.prank(executor);
        registry.register{value: stake}();

        (uint256 stakedAmount,,,,,) = registry.executors(executor);
        assertEq(stakedAmount, stake);
    }
}
