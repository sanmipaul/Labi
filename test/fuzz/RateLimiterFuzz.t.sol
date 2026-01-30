// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/RateLimiter.sol";

/**
 * @title RateLimiterFuzzTest
 * @notice Fuzz tests for RateLimiter timing logic
 */
contract RateLimiterFuzzTest is Test {
    RateLimiter public rateLimiter;
    address public vault;

    function setUp() public {
        rateLimiter = new RateLimiter();
        vault = address(0x1111);
    }

    /**
     * @notice Fuzz test: Minimum interval calculation
     * @param limit Executions per day
     */
    function testFuzz_MinimumIntervalCalculation(uint256 limit) public {
        limit = bound(limit, 1, 86400); // Max 1 per second

        rateLimiter.setExecutionLimitPerDay(vault, limit);

        uint256 expectedInterval = 1 days / limit;
        uint256 actualInterval = rateLimiter.getMinimumInterval(vault);

        assertEq(actualInterval, expectedInterval);
    }

    /**
     * @notice Fuzz test: First execution always allowed
     * @param flowId Random flow ID
     * @param limit Executions per day
     */
    function testFuzz_FirstExecutionAlwaysAllowed(uint256 flowId, uint256 limit) public {
        limit = bound(limit, 1, 1000);

        rateLimiter.setExecutionLimitPerDay(vault, limit);

        // First execution should always be allowed
        assertTrue(rateLimiter.canExecute(vault, flowId));
    }

    /**
     * @notice Fuzz test: Execution blocked within interval
     * @param flowId Random flow ID
     * @param limit Executions per day
     * @param elapsedTime Time since last execution
     */
    function testFuzz_ExecutionBlockedWithinInterval(
        uint256 flowId,
        uint256 limit,
        uint256 elapsedTime
    ) public {
        limit = bound(limit, 1, 100);
        uint256 minInterval = 1 days / limit;
        elapsedTime = bound(elapsedTime, 0, minInterval - 1);

        rateLimiter.setExecutionLimitPerDay(vault, limit);
        rateLimiter.recordExecution(vault, flowId);

        // Warp time but stay within interval
        vm.warp(block.timestamp + elapsedTime);

        // Should be blocked
        assertFalse(rateLimiter.canExecute(vault, flowId));
    }

    /**
     * @notice Fuzz test: Execution allowed after interval
     * @param flowId Random flow ID
     * @param limit Executions per day
     * @param extraTime Extra time beyond interval
     */
    function testFuzz_ExecutionAllowedAfterInterval(
        uint256 flowId,
        uint256 limit,
        uint256 extraTime
    ) public {
        limit = bound(limit, 1, 100);
        extraTime = bound(extraTime, 0, 1 days);
        uint256 minInterval = 1 days / limit;

        rateLimiter.setExecutionLimitPerDay(vault, limit);
        rateLimiter.recordExecution(vault, flowId);

        // Warp time past interval
        vm.warp(block.timestamp + minInterval + extraTime);

        // Should be allowed
        assertTrue(rateLimiter.canExecute(vault, flowId));
    }

    /**
     * @notice Fuzz test: Different flows are independent
     * @param flowId1 First flow ID
     * @param flowId2 Second flow ID
     * @param limit Executions per day
     */
    function testFuzz_FlowsAreIndependent(
        uint256 flowId1,
        uint256 flowId2,
        uint256 limit
    ) public {
        vm.assume(flowId1 != flowId2);
        limit = bound(limit, 1, 100);

        rateLimiter.setExecutionLimitPerDay(vault, limit);

        // Record execution for flow 1
        rateLimiter.recordExecution(vault, flowId1);

        // Flow 1 blocked, flow 2 still allowed
        assertFalse(rateLimiter.canExecute(vault, flowId1));
        assertTrue(rateLimiter.canExecute(vault, flowId2));
    }

    /**
     * @notice Fuzz test: Different vaults are independent
     * @param vault1 First vault address
     * @param vault2 Second vault address
     * @param flowId Flow ID
     * @param limit Executions per day
     */
    function testFuzz_VaultsAreIndependent(
        address vault1,
        address vault2,
        uint256 flowId,
        uint256 limit
    ) public {
        vm.assume(vault1 != address(0) && vault2 != address(0));
        vm.assume(vault1 != vault2);
        limit = bound(limit, 1, 100);

        rateLimiter.setExecutionLimitPerDay(vault1, limit);
        rateLimiter.setExecutionLimitPerDay(vault2, limit);

        // Record execution for vault 1
        rateLimiter.recordExecution(vault1, flowId);

        // Vault 1 blocked, vault 2 still allowed
        assertFalse(rateLimiter.canExecute(vault1, flowId));
        assertTrue(rateLimiter.canExecute(vault2, flowId));
    }
}
