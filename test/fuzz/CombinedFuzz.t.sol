// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/IntentVault.sol";
import "../../src/RateLimiter.sol";

/**
 * @title CombinedFuzzTest
 * @notice Combined fuzz tests for multiple contract interactions
 */
contract CombinedFuzzTest is Test {
    IntentVault public vault;
    RateLimiter public rateLimiter;

    address public owner;
    address public protocol;
    address public token;

    function setUp() public {
        owner = address(this);
        protocol = address(0x1111);
        token = address(0x2222);

        vault = new IntentVault(address(0x1234));
        rateLimiter = new RateLimiter();

        vault.approveProtocol(protocol);
    }

    /**
     * @notice Fuzz test: Vault spending with rate limiting
     * @param cap Spending cap
     * @param spendAmount Amount to spend
     * @param limit Rate limit per day
     */
    function testFuzz_VaultSpendingWithRateLimit(
        uint256 cap,
        uint256 spendAmount,
        uint256 limit
    ) public {
        cap = bound(cap, 1, type(uint128).max);
        spendAmount = bound(spendAmount, 1, cap);
        limit = bound(limit, 1, 24);

        vault.setSpendingCap(token, cap);
        rateLimiter.setExecutionLimitPerDay(address(vault), limit);

        // First execution should be allowed
        assertTrue(rateLimiter.canExecute(address(vault), 1));

        // Record spending
        vm.prank(protocol);
        vault.recordSpending(token, spendAmount);

        // Record rate limit execution
        rateLimiter.recordExecution(address(vault), 1);

        // Verify state
        assertEq(vault.getRemainingSpendingCap(token), cap - spendAmount);
        assertFalse(rateLimiter.canExecute(address(vault), 1));
    }

    /**
     * @notice Fuzz test: Multiple tokens with rate limiting
     * @param caps Array of caps for different tokens
     * @param amounts Array of spend amounts
     */
    function testFuzz_MultiTokenRateLimited(
        uint256[3] memory caps,
        uint256[3] memory amounts
    ) public {
        address[3] memory tokens = [address(0x1), address(0x2), address(0x3)];

        for (uint256 i = 0; i < 3; i++) {
            caps[i] = bound(caps[i], 1000, type(uint128).max);
            amounts[i] = bound(amounts[i], 1, caps[i]);

            vault.setSpendingCap(tokens[i], caps[i]);
        }

        rateLimiter.setExecutionLimitPerDay(address(vault), 10);

        // Spend from each token
        for (uint256 i = 0; i < 3; i++) {
            assertTrue(rateLimiter.canExecute(address(vault), i));

            vm.prank(protocol);
            vault.recordSpending(tokens[i], amounts[i]);

            rateLimiter.recordExecution(address(vault), i);

            assertEq(vault.getRemainingSpendingCap(tokens[i]), caps[i] - amounts[i]);
        }
    }

    /**
     * @notice Fuzz test: Pause state with rate limiter
     * @param timestamp Timestamp to warp to
     */
    function testFuzz_PauseStateWithRateLimiter(uint256 timestamp) public {
        timestamp = bound(timestamp, block.timestamp, type(uint64).max);

        vault.setSpendingCap(token, 1000e18);
        rateLimiter.setExecutionLimitPerDay(address(vault), 5);

        vm.warp(timestamp);

        // Record execution in rate limiter
        rateLimiter.recordExecution(address(vault), 1);

        // Pause vault
        vault.pause();

        // Rate limiter still tracks (independent of vault pause)
        assertFalse(rateLimiter.canExecute(address(vault), 1));

        // But vault spending is blocked
        vm.prank(protocol);
        vm.expectRevert("IntentVault: vault is paused");
        vault.recordSpending(token, 100e18);
    }

    /**
     * @notice Fuzz test: Sequential operations over time
     * @param operations Number of operations
     * @param timeJumps Time between operations
     */
    function testFuzz_SequentialOperationsOverTime(
        uint256 operations,
        uint256 timeJumps
    ) public {
        operations = bound(operations, 1, 10);
        timeJumps = bound(timeJumps, 1 hours, 12 hours);

        vault.setSpendingCap(token, 10000e18);
        rateLimiter.setExecutionLimitPerDay(address(vault), 24);

        uint256 totalSpent = 0;

        for (uint256 i = 0; i < operations; i++) {
            // Wait for rate limit
            if (i > 0) {
                vm.warp(block.timestamp + timeJumps);
            }

            if (rateLimiter.canExecute(address(vault), 1) && totalSpent < 9000e18) {
                uint256 spendAmount = 100e18;

                vm.prank(protocol);
                vault.recordSpending(token, spendAmount);

                rateLimiter.recordExecution(address(vault), 1);
                totalSpent += spendAmount;
            }
        }

        // Verify final state
        assertEq(vault.getRemainingSpendingCap(token), 10000e18 - totalSpent);
    }

    /**
     * @notice Fuzz test: Protocol approval changes during operations
     * @param newProtocol New protocol address
     */
    function testFuzz_ProtocolApprovalChanges(address newProtocol) public {
        vm.assume(newProtocol != address(0));
        vm.assume(newProtocol != protocol);

        vault.setSpendingCap(token, 1000e18);

        // Original protocol can spend
        vm.prank(protocol);
        vault.recordSpending(token, 100e18);

        // Revoke original, approve new
        vault.revokeProtocol(protocol);
        vault.approveProtocol(newProtocol);

        // Original can't spend
        vm.prank(protocol);
        vm.expectRevert("IntentVault: protocol not approved");
        vault.recordSpending(token, 100e18);

        // New protocol can spend
        vm.prank(newProtocol);
        vault.recordSpending(token, 100e18);

        assertEq(vault.getRemainingSpendingCap(token), 800e18);
    }
}
