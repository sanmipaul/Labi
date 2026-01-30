// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../src/RateLimiter.sol";

/**
 * @title RateLimiterHandler
 * @notice Handler contract for RateLimiter invariant testing
 */
contract RateLimiterHandler is Test {
    RateLimiter public rateLimiter;
    address public vault;

    uint256 public ghost_limit;
    mapping(uint256 => uint256) public ghost_lastExecution;
    uint256 public ghost_callCount;

    constructor(RateLimiter _rateLimiter, address _vault) {
        rateLimiter = _rateLimiter;
        vault = _vault;
    }

    function setLimit(uint256 limit) external {
        limit = bound(limit, 1, 1000);

        rateLimiter.setExecutionLimitPerDay(vault, limit);
        ghost_limit = limit;
        ghost_callCount++;
    }

    function recordExecution(uint256 flowId) external {
        flowId = bound(flowId, 1, 100);

        rateLimiter.recordExecution(vault, flowId);
        ghost_lastExecution[flowId] = block.timestamp;
        ghost_callCount++;
    }

    function warpTime(uint256 seconds_) external {
        seconds_ = bound(seconds_, 1, 2 days);
        vm.warp(block.timestamp + seconds_);
        ghost_callCount++;
    }
}

/**
 * @title RateLimiterInvariantTest
 * @notice Invariant tests for RateLimiter
 */
contract RateLimiterInvariantTest is StdInvariant, Test {
    RateLimiter public rateLimiter;
    RateLimiterHandler public handler;
    address public vault;

    function setUp() public {
        vault = address(0x1111);

        rateLimiter = new RateLimiter();
        rateLimiter.setExecutionLimitPerDay(vault, 10);

        handler = new RateLimiterHandler(rateLimiter, vault);

        targetContract(address(handler));
    }

    /**
     * @notice Invariant: Minimum interval is calculated correctly
     */
    function invariant_MinIntervalCalculation() public {
        uint256 limit = rateLimiter.executionLimitPerDay(vault);

        if (limit > 0) {
            uint256 expectedInterval = 1 days / limit;
            uint256 actualInterval = rateLimiter.getMinimumInterval(vault);

            assertEq(actualInterval, expectedInterval);
        }
    }

    /**
     * @notice Invariant: Last execution time is never in the future
     */
    function invariant_LastExecutionNotFuture() public {
        for (uint256 flowId = 1; flowId <= 10; flowId++) {
            uint256 lastExec = rateLimiter.getLastExecutionTime(vault, flowId);

            if (lastExec > 0) {
                assertLe(lastExec, block.timestamp);
            }
        }
    }

    /**
     * @notice Invariant: First execution is always allowed
     */
    function invariant_FirstExecutionAllowed() public {
        // Test with a flow that has never been executed
        uint256 newFlowId = 999999;
        assertTrue(rateLimiter.canExecute(vault, newFlowId));
    }
}
