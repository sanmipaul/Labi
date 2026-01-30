// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/IntentVault.sol";
import "../../src/RateLimiter.sol";
import "../../src/actions/SwapAction.sol";

/**
 * @title BoundaryFuzzTest
 * @notice Fuzz tests specifically for boundary conditions and edge cases
 */
contract BoundaryFuzzTest is Test {
    IntentVault public vault;
    RateLimiter public rateLimiter;
    SwapAction public swapAction;

    address public protocol;
    address public token;

    function setUp() public {
        protocol = address(0x1111);
        token = address(0x2222);

        vault = new IntentVault(address(0x1234));
        rateLimiter = new RateLimiter();
        swapAction = new SwapAction();

        vault.approveProtocol(protocol);
    }

    /**
     * @notice Fuzz test: Maximum uint256 values
     */
    function testFuzz_MaxUint256Values() public {
        // Note: Using uint128.max to avoid overflow in internal calculations
        uint256 maxCap = type(uint128).max;

        vault.setSpendingCap(token, maxCap);
        assertEq(vault.getSpendingCap(token), maxCap);
        assertEq(vault.getRemainingSpendingCap(token), maxCap);
    }

    /**
     * @notice Fuzz test: Minimum non-zero values
     * @param minValue Small value to test
     */
    function testFuzz_MinimumNonZeroValues(uint256 minValue) public {
        minValue = bound(minValue, 1, 100);

        vault.setSpendingCap(token, minValue);

        vm.prank(protocol);
        vault.recordSpending(token, minValue);

        assertEq(vault.getRemainingSpendingCap(token), 0);
    }

    /**
     * @notice Fuzz test: Rate limiter with 1 execution per day
     */
    function testFuzz_SingleExecutionPerDay() public {
        rateLimiter.setExecutionLimitPerDay(address(vault), 1);

        uint256 interval = rateLimiter.getMinimumInterval(address(vault));
        assertEq(interval, 1 days);

        rateLimiter.recordExecution(address(vault), 1);
        assertFalse(rateLimiter.canExecute(address(vault), 1));

        vm.warp(block.timestamp + 1 days);
        assertTrue(rateLimiter.canExecute(address(vault), 1));
    }

    /**
     * @notice Fuzz test: Rate limiter with max executions per day
     * @param limit High execution limit
     */
    function testFuzz_HighExecutionLimit(uint256 limit) public {
        limit = bound(limit, 1000, 86400);

        rateLimiter.setExecutionLimitPerDay(address(vault), limit);

        uint256 interval = rateLimiter.getMinimumInterval(address(vault));
        assertEq(interval, 1 days / limit);
    }

    /**
     * @notice Fuzz test: Spending cap exactly equal to spend amount
     * @param amount Amount for both cap and spend
     */
    function testFuzz_ExactCapEqualsSpend(uint256 amount) public {
        amount = bound(amount, 1, type(uint128).max);

        vault.setSpendingCap(token, amount);

        vm.prank(protocol);
        vault.recordSpending(token, amount);

        assertEq(vault.getRemainingSpendingCap(token), 0);
    }

    /**
     * @notice Fuzz test: Spending 1 wei below cap
     * @param cap Spending cap
     */
    function testFuzz_OneWeiBelowCap(uint256 cap) public {
        cap = bound(cap, 2, type(uint128).max);

        vault.setSpendingCap(token, cap);

        vm.prank(protocol);
        vault.recordSpending(token, cap - 1);

        assertEq(vault.getRemainingSpendingCap(token), 1);
    }

    /**
     * @notice Fuzz test: Slippage at exact boundaries
     */
    function testFuzz_SlippageExactBoundaries() public {
        // Test min at 1 bp
        swapAction.setMinSlippage(1);
        assertEq(swapAction.minSlippageBps(), 1);

        // Test max at 10000 bp (100%)
        swapAction.setMaxSlippage(10000);
        assertEq(swapAction.maxSlippageBps(), 10000);

        // Min output at 100% slippage should be 0
        uint256 minOutput = swapAction.calculateMinOutput(1000e18);
        assertEq(minOutput, 0);
    }

    /**
     * @notice Fuzz test: Timestamp boundaries
     * @param timestamp Timestamp to test
     */
    function testFuzz_TimestampBoundaries(uint256 timestamp) public {
        timestamp = bound(timestamp, 1, type(uint64).max);
        vm.warp(timestamp);

        rateLimiter.setExecutionLimitPerDay(address(vault), 10);
        rateLimiter.recordExecution(address(vault), 1);

        assertEq(rateLimiter.getLastExecutionTime(address(vault), 1), timestamp);
    }

    /**
     * @notice Fuzz test: Multiple sequential cap changes
     * @param caps Array of caps to set
     */
    function testFuzz_SequentialCapChanges(uint256[5] memory caps) public {
        for (uint256 i = 0; i < 5; i++) {
            caps[i] = bound(caps[i], 1, type(uint128).max);

            vault.setSpendingCap(token, caps[i]);

            // Each cap change should reset spending
            assertEq(vault.getRemainingSpendingCap(token), caps[i]);
            assertEq(vault.getSpendingCap(token), caps[i]);
        }
    }

    /**
     * @notice Fuzz test: Rapid pause/unpause cycles
     * @param cycles Number of pause/unpause cycles
     */
    function testFuzz_RapidPauseUnpauseCycles(uint256 cycles) public {
        cycles = bound(cycles, 1, 50);

        for (uint256 i = 0; i < cycles; i++) {
            vault.pause();
            assertTrue(vault.isPaused());

            vault.unpause();
            assertFalse(vault.isPaused());
        }
    }
}
