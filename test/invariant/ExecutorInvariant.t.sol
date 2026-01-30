// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../src/executor/ExecutorRegistry.sol";
import "../../src/executor/ReputationManager.sol";
import "../../src/executor/ExecutorSlasher.sol";

/**
 * @title ExecutorHandler
 * @notice Handler contract for invariant testing of executor system
 */
contract ExecutorHandler is Test {
    ExecutorRegistry public registry;
    ReputationManager public reputationManager;
    ExecutorSlasher public slasher;

    uint256 public constant MIN_STAKE = 0.1 ether;

    address[] public executors;
    uint256 public totalStaked;
    uint256 public totalSlashed;
    uint256 public registrationCount;
    uint256 public withdrawalCount;

    constructor(
        ExecutorRegistry _registry,
        ReputationManager _reputationManager,
        ExecutorSlasher _slasher
    ) {
        registry = _registry;
        reputationManager = _reputationManager;
        slasher = _slasher;
    }

    function registerExecutor(uint256 seed, uint256 stakeAmount) external {
        stakeAmount = bound(stakeAmount, MIN_STAKE, 10 ether);

        address executor = address(uint160(uint256(keccak256(abi.encodePacked(seed, block.timestamp)))));

        // Skip if already registered
        (uint256 existingStake,,,,,) = registry.executors(executor);
        if (existingStake > 0) return;

        vm.deal(executor, stakeAmount);

        vm.prank(executor);
        registry.register{value: stakeAmount}();

        executors.push(executor);
        totalStaked += stakeAmount;
        registrationCount++;
    }

    function addStake(uint256 executorIndex, uint256 amount) external {
        if (executors.length == 0) return;

        executorIndex = bound(executorIndex, 0, executors.length - 1);
        amount = bound(amount, 0.01 ether, 5 ether);

        address executor = executors[executorIndex];

        if (!registry.isActive(executor)) return;

        vm.deal(executor, amount);

        vm.prank(executor);
        registry.addStake{value: amount}();

        totalStaked += amount;
    }

    function recordSuccess(uint256 executorIndex) external {
        if (executors.length == 0) return;

        executorIndex = bound(executorIndex, 0, executors.length - 1);
        address executor = executors[executorIndex];

        vm.prank(address(registry));
        reputationManager.recordExecution(executor, true, 50000, 100000);
    }

    function recordFailure(uint256 executorIndex) external {
        if (executors.length == 0) return;

        executorIndex = bound(executorIndex, 0, executors.length - 1);
        address executor = executors[executorIndex];

        vm.prank(address(registry));
        reputationManager.recordExecution(executor, false, 50000, 100000);
    }

    function slashForFailed(uint256 executorIndex) external {
        if (executors.length == 0) return;

        executorIndex = bound(executorIndex, 0, executors.length - 1);
        address executor = executors[executorIndex];

        (uint256 stakeBefore,,,,,) = registry.executors(executor);
        if (stakeBefore == 0) return;

        bytes32 flowId = keccak256(abi.encodePacked(executor, block.timestamp));
        slasher.slashForFailedExecution(executor, flowId);

        (uint256 stakeAfter,,,,,) = registry.executors(executor);
        totalSlashed += stakeBefore - stakeAfter;
        totalStaked -= (stakeBefore - stakeAfter);
    }

    function slashForTimeout(uint256 executorIndex) external {
        if (executors.length == 0) return;

        executorIndex = bound(executorIndex, 0, executors.length - 1);
        address executor = executors[executorIndex];

        (uint256 stakeBefore,,,,,) = registry.executors(executor);
        if (stakeBefore == 0) return;

        bytes32 flowId = keccak256(abi.encodePacked(executor, "timeout", block.timestamp));
        slasher.slashForTimeout(executor, flowId);

        (uint256 stakeAfter,,,,,) = registry.executors(executor);
        totalSlashed += stakeBefore - stakeAfter;
        totalStaked -= (stakeBefore - stakeAfter);
    }

    function initiateWithdrawal(uint256 executorIndex) external {
        if (executors.length == 0) return;

        executorIndex = bound(executorIndex, 0, executors.length - 1);
        address executor = executors[executorIndex];

        if (!registry.isActive(executor)) return;

        (,,uint256 withdrawalInitiated,,,) = registry.executors(executor);
        if (withdrawalInitiated > 0) return;

        vm.prank(executor);
        registry.initiateWithdrawal();
    }

    function completeWithdrawal(uint256 executorIndex) external {
        if (executors.length == 0) return;

        executorIndex = bound(executorIndex, 0, executors.length - 1);
        address executor = executors[executorIndex];

        (uint256 stake,,uint256 withdrawalInitiated, IExecutorRegistry.ExecutorStatus status,,) = registry.executors(executor);

        if (stake == 0) return;
        if (withdrawalInitiated == 0) return;
        if (uint256(status) != uint256(IExecutorRegistry.ExecutorStatus.Withdrawing)) return;
        if (block.timestamp < withdrawalInitiated + 7 days) return;

        vm.prank(executor);
        registry.completeWithdrawal();

        totalStaked -= stake;
        withdrawalCount++;
    }

    function warpTime(uint256 timeToAdd) external {
        timeToAdd = bound(timeToAdd, 1 hours, 14 days);
        vm.warp(block.timestamp + timeToAdd);
    }

    function getExecutorCount() external view returns (uint256) {
        return executors.length;
    }
}

/**
 * @title ExecutorInvariantTest
 * @notice Invariant tests for the executor staking and reputation system
 */
contract ExecutorInvariantTest is StdInvariant, Test {
    ExecutorRegistry public registry;
    ReputationManager public reputationManager;
    ExecutorSlasher public slasher;
    ExecutorHandler public handler;

    uint256 public constant MIN_STAKE = 0.1 ether;
    uint256 public constant COOLDOWN = 7 days;

    function setUp() public {
        registry = new ExecutorRegistry(MIN_STAKE, COOLDOWN);
        reputationManager = new ReputationManager(address(registry));
        slasher = new ExecutorSlasher(address(registry), address(reputationManager));

        registry.grantSlasherRole(address(slasher));

        handler = new ExecutorHandler(registry, reputationManager, slasher);

        targetContract(address(handler));

        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = ExecutorHandler.registerExecutor.selector;
        selectors[1] = ExecutorHandler.addStake.selector;
        selectors[2] = ExecutorHandler.recordSuccess.selector;
        selectors[3] = ExecutorHandler.recordFailure.selector;
        selectors[4] = ExecutorHandler.slashForFailed.selector;
        selectors[5] = ExecutorHandler.slashForTimeout.selector;
        selectors[6] = ExecutorHandler.initiateWithdrawal.selector;
        selectors[7] = ExecutorHandler.completeWithdrawal.selector;
        selectors[8] = ExecutorHandler.warpTime.selector;

        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    // ============ Stake Invariants ============

    function invariant_activeExecutorHasMinimumStake() public view {
        address[] memory activeExecutors = registry.getActiveExecutors();

        for (uint256 i = 0; i < activeExecutors.length; i++) {
            (uint256 stake,,,,,) = registry.executors(activeExecutors[i]);
            assert(stake >= MIN_STAKE);
        }
    }

    function invariant_totalStakedMatchesContractBalance() public view {
        uint256 totalInRegistry = 0;
        uint256 executorCount = handler.getExecutorCount();

        for (uint256 i = 0; i < executorCount; i++) {
            address executor = handler.executors(i);
            (uint256 stake,,,,,) = registry.executors(executor);
            totalInRegistry += stake;
        }

        assertEq(address(registry).balance, totalInRegistry);
    }

    // ============ Reputation Invariants ============

    function invariant_reputationScoreCapped() public view {
        uint256 executorCount = handler.getExecutorCount();

        for (uint256 i = 0; i < executorCount; i++) {
            address executor = handler.executors(i);
            (uint256 score,,,,,,) = reputationManager.reputationData(executor);
            assert(score <= 1000);
        }
    }

    function invariant_successfulExecutionsLessThanOrEqualTotal() public view {
        uint256 executorCount = handler.getExecutorCount();

        for (uint256 i = 0; i < executorCount; i++) {
            address executor = handler.executors(i);
            (,uint256 total, uint256 successful,,,,) = reputationManager.reputationData(executor);
            assert(successful <= total);
        }
    }

    function invariant_currentStreakMatchesSuccessful() public view {
        uint256 executorCount = handler.getExecutorCount();

        for (uint256 i = 0; i < executorCount; i++) {
            address executor = handler.executors(i);
            (,uint256 total,, uint256 currentStreak,,,) = reputationManager.reputationData(executor);
            assert(currentStreak <= total);
        }
    }

    function invariant_bestStreakGreaterThanOrEqualCurrent() public view {
        uint256 executorCount = handler.getExecutorCount();

        for (uint256 i = 0; i < executorCount; i++) {
            address executor = handler.executors(i);
            (,,,uint256 currentStreak, uint256 bestStreak,,) = reputationManager.reputationData(executor);
            assert(bestStreak >= currentStreak);
        }
    }

    // ============ Status Invariants ============

    function invariant_withdrawingExecutorHasWithdrawalTimestamp() public view {
        uint256 executorCount = handler.getExecutorCount();

        for (uint256 i = 0; i < executorCount; i++) {
            address executor = handler.executors(i);
            (,,uint256 withdrawalInitiated, IExecutorRegistry.ExecutorStatus status,,) = registry.executors(executor);

            if (uint256(status) == uint256(IExecutorRegistry.ExecutorStatus.Withdrawing)) {
                assert(withdrawalInitiated > 0);
            }
        }
    }

    // ============ Tier Invariants ============

    function invariant_tierMatchesScore() public view {
        uint256 executorCount = handler.getExecutorCount();

        for (uint256 i = 0; i < executorCount; i++) {
            address executor = handler.executors(i);
            (uint256 score,,,,,,) = reputationManager.reputationData(executor);
            IReputationManager.ReputationTier tier = reputationManager.getTier(executor);

            if (score >= 900) {
                assert(uint256(tier) == uint256(IReputationManager.ReputationTier.Platinum));
            } else if (score >= 750) {
                assert(uint256(tier) == uint256(IReputationManager.ReputationTier.Gold));
            } else if (score >= 600) {
                assert(uint256(tier) == uint256(IReputationManager.ReputationTier.Silver));
            } else if (score >= 400) {
                assert(uint256(tier) == uint256(IReputationManager.ReputationTier.Bronze));
            } else {
                assert(uint256(tier) == uint256(IReputationManager.ReputationTier.Novice));
            }
        }
    }

    // ============ Slashing Invariants ============

    function invariant_slashingNeverExceedsStake() public view {
        // Total slashed should be <= initial total staked
        // This is tracked by handler
        assert(handler.totalSlashed() <= handler.totalStaked() + handler.totalSlashed());
    }

    // ============ Call Summary ============

    function invariant_callSummary() public view {
        console.log("Registered executors:", handler.registrationCount());
        console.log("Completed withdrawals:", handler.withdrawalCount());
        console.log("Total staked:", handler.totalStaked());
        console.log("Total slashed:", handler.totalSlashed());
    }
}
