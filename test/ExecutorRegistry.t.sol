// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/executor/ExecutorRegistry.sol";

contract ExecutorRegistryTest is Test {
    ExecutorRegistry public registry;
    address public owner;
    address public executor1;
    address public executor2;
    address public treasury;

    uint256 constant MINIMUM_STAKE = 1 ether;
    uint256 constant WITHDRAWAL_COOLDOWN = 7 days;

    event ExecutorRegistered(address indexed executor, uint256 stakedAmount);
    event ExecutorStakeIncreased(address indexed executor, uint256 additionalStake, uint256 totalStake);
    event ExecutorStakeWithdrawn(address indexed executor, uint256 amount, uint256 remainingStake);
    event ExecutorSuspended(address indexed executor, string reason);
    event ExecutorReactivated(address indexed executor);
    event ExecutorSlashed(address indexed executor, uint256 slashAmount, string reason);

    function setUp() public {
        owner = address(this);
        executor1 = makeAddr("executor1");
        executor2 = makeAddr("executor2");
        treasury = makeAddr("treasury");

        registry = new ExecutorRegistry(MINIMUM_STAKE, WITHDRAWAL_COOLDOWN, treasury);

        // Fund executors
        vm.deal(executor1, 10 ether);
        vm.deal(executor2, 10 ether);
    }

    function test_RegisterExecutor() public {
        vm.prank(executor1);
        registry.registerExecutor{value: 2 ether}();

        assertTrue(registry.isActiveExecutor(executor1));
        assertEq(registry.getStakedAmount(executor1), 2 ether);

        IExecutorRegistry.ExecutorInfo memory info = registry.getExecutorInfo(executor1);
        assertEq(info.executor, executor1);
        assertEq(info.stakedAmount, 2 ether);
        assertEq(uint8(info.status), uint8(IExecutorRegistry.ExecutorStatus.Active));
    }

    function test_RegisterExecutorEmitsEvent() public {
        vm.prank(executor1);
        vm.expectEmit(true, false, false, true);
        emit ExecutorRegistered(executor1, 2 ether);
        registry.registerExecutor{value: 2 ether}();
    }

    function test_RevertRegisterWithInsufficientStake() public {
        vm.prank(executor1);
        vm.expectRevert("ExecutorRegistry: insufficient stake");
        registry.registerExecutor{value: 0.5 ether}();
    }

    function test_RevertRegisterAlreadyRegistered() public {
        vm.prank(executor1);
        registry.registerExecutor{value: 1 ether}();

        vm.prank(executor1);
        vm.expectRevert("ExecutorRegistry: already registered");
        registry.registerExecutor{value: 1 ether}();
    }

    function test_IncreaseStake() public {
        vm.startPrank(executor1);
        registry.registerExecutor{value: 1 ether}();
        registry.increaseStake{value: 0.5 ether}();
        vm.stopPrank();

        assertEq(registry.getStakedAmount(executor1), 1.5 ether);
    }

    function test_RequestAndWithdrawStake() public {
        vm.startPrank(executor1);
        registry.registerExecutor{value: 2 ether}();

        registry.requestWithdrawal();

        // Warp past cooldown
        vm.warp(block.timestamp + WITHDRAWAL_COOLDOWN + 1);

        uint256 balanceBefore = executor1.balance;
        registry.withdrawStake(1 ether);
        uint256 balanceAfter = executor1.balance;
        vm.stopPrank();

        assertEq(balanceAfter - balanceBefore, 1 ether);
        assertEq(registry.getStakedAmount(executor1), 1 ether);
    }

    function test_RevertWithdrawBeforeCooldown() public {
        vm.startPrank(executor1);
        registry.registerExecutor{value: 2 ether}();
        registry.requestWithdrawal();

        vm.expectRevert("ExecutorRegistry: cooldown not elapsed");
        registry.withdrawStake(1 ether);
        vm.stopPrank();
    }

    function test_RevertWithdrawWithoutRequest() public {
        vm.startPrank(executor1);
        registry.registerExecutor{value: 2 ether}();

        vm.expectRevert("ExecutorRegistry: withdrawal not requested");
        registry.withdrawStake(1 ether);
        vm.stopPrank();
    }

    function test_SuspendExecutor() public {
        vm.prank(executor1);
        registry.registerExecutor{value: 1 ether}();

        registry.suspendExecutor(executor1, "Test suspension");

        assertFalse(registry.isActiveExecutor(executor1));

        IExecutorRegistry.ExecutorInfo memory info = registry.getExecutorInfo(executor1);
        assertEq(uint8(info.status), uint8(IExecutorRegistry.ExecutorStatus.Suspended));
    }

    function test_ReactivateExecutor() public {
        vm.prank(executor1);
        registry.registerExecutor{value: 1 ether}();

        registry.suspendExecutor(executor1, "Test suspension");
        registry.reactivateExecutor(executor1);

        assertTrue(registry.isActiveExecutor(executor1));
    }

    function test_SlashExecutor() public {
        vm.prank(executor1);
        registry.registerExecutor{value: 2 ether}();

        uint256 treasuryBefore = treasury.balance;

        registry.slashExecutor(executor1, 0.5 ether, "Test slash");

        uint256 treasuryAfter = treasury.balance;

        assertEq(registry.getStakedAmount(executor1), 1.5 ether);
        assertEq(treasuryAfter - treasuryBefore, 0.5 ether);

        IExecutorRegistry.ExecutorInfo memory info = registry.getExecutorInfo(executor1);
        assertEq(uint8(info.status), uint8(IExecutorRegistry.ExecutorStatus.Slashed));
    }

    function test_RecordExecution() public {
        vm.prank(executor1);
        registry.registerExecutor{value: 1 ether}();

        registry.setAuthorizedCaller(address(this), true);
        registry.recordExecution(executor1, 1, true);
        registry.recordExecution(executor1, 2, false);

        IExecutorRegistry.ExecutorInfo memory info = registry.getExecutorInfo(executor1);
        assertEq(info.totalExecutions, 2);
        assertEq(info.successfulExecutions, 1);
        assertEq(info.failedExecutions, 1);
    }

    function test_GetTotalExecutors() public {
        vm.prank(executor1);
        registry.registerExecutor{value: 1 ether}();

        vm.prank(executor2);
        registry.registerExecutor{value: 1 ether}();

        assertEq(registry.getTotalExecutors(), 2);
    }

    function test_GetExecutorByIndex() public {
        vm.prank(executor1);
        registry.registerExecutor{value: 1 ether}();

        vm.prank(executor2);
        registry.registerExecutor{value: 1 ether}();

        assertEq(registry.getExecutorByIndex(0), executor1);
        assertEq(registry.getExecutorByIndex(1), executor2);
    }

    function test_OnlyOwnerCanSuspend() public {
        vm.prank(executor1);
        registry.registerExecutor{value: 1 ether}();

        vm.prank(executor2);
        vm.expectRevert("ExecutorRegistry: caller is not owner");
        registry.suspendExecutor(executor1, "Test");
    }

    function test_OnlyOwnerCanSlash() public {
        vm.prank(executor1);
        registry.registerExecutor{value: 1 ether}();

        vm.prank(executor2);
        vm.expectRevert("ExecutorRegistry: caller is not owner");
        registry.slashExecutor(executor1, 0.5 ether, "Test");
    }

    function test_SetMinimumStake() public {
        registry.setMinimumStake(2 ether);
        assertEq(registry.getMinimumStake(), 2 ether);
    }

    function test_SetWithdrawalCooldown() public {
        registry.setWithdrawalCooldown(14 days);
        assertEq(registry.withdrawalCooldown(), 14 days);
    }
}
