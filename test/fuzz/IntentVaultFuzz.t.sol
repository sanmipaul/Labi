// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/IntentVault.sol";

/**
 * @title IntentVaultFuzzTest
 * @notice Fuzz tests for IntentVault spending cap enforcement
 */
contract IntentVaultFuzzTest is Test {
    IntentVault public vault;
    address public owner;
    address public protocol;
    address public token;

    function setUp() public {
        owner = address(this);
        protocol = address(0x1111);
        token = address(0x2222);

        vault = new IntentVault(address(0x1234));
        vault.approveProtocol(protocol);
    }

    /**
     * @notice Fuzz test: Spending cap should never be exceeded
     * @param cap The spending cap to set
     * @param spendAmount The amount to spend
     */
    function testFuzz_SpendingCapNeverExceeded(uint256 cap, uint256 spendAmount) public {
        // Bound inputs to reasonable values
        cap = bound(cap, 1, type(uint128).max);
        spendAmount = bound(spendAmount, 1, type(uint128).max);

        vault.setSpendingCap(token, cap);

        vm.prank(protocol);
        if (spendAmount <= cap) {
            vault.recordSpending(token, spendAmount);
            assertLe(cap - vault.getRemainingSpendingCap(token), cap);
        } else {
            vm.expectRevert("IntentVault: spending cap exceeded");
            vault.recordSpending(token, spendAmount);
        }
    }

    /**
     * @notice Fuzz test: Remaining cap calculation is always correct
     * @param cap The spending cap to set
     * @param spendAmount The amount to spend
     */
    function testFuzz_RemainingCapCalculation(uint256 cap, uint256 spendAmount) public {
        cap = bound(cap, 1, type(uint128).max);
        spendAmount = bound(spendAmount, 1, cap);

        vault.setSpendingCap(token, cap);

        vm.prank(protocol);
        vault.recordSpending(token, spendAmount);

        uint256 remaining = vault.getRemainingSpendingCap(token);
        assertEq(remaining, cap - spendAmount);
    }

    /**
     * @notice Fuzz test: Multiple spending operations accumulate correctly
     * @param cap The spending cap
     * @param amounts Array of spend amounts
     */
    function testFuzz_CumulativeSpending(uint256 cap, uint256[5] memory amounts) public {
        cap = bound(cap, 1000, type(uint128).max);

        vault.setSpendingCap(token, cap);

        uint256 totalSpent = 0;

        for (uint256 i = 0; i < 5; i++) {
            amounts[i] = bound(amounts[i], 1, cap / 10);

            if (totalSpent + amounts[i] <= cap) {
                vm.prank(protocol);
                vault.recordSpending(token, amounts[i]);
                totalSpent += amounts[i];

                uint256 remaining = vault.getRemainingSpendingCap(token);
                assertEq(remaining, cap - totalSpent);
            }
        }
    }

    /**
     * @notice Fuzz test: Setting new cap resets spent amount
     * @param initialCap Initial spending cap
     * @param spendAmount Amount to spend
     * @param newCap New spending cap
     */
    function testFuzz_CapResetOnNewCap(uint256 initialCap, uint256 spendAmount, uint256 newCap) public {
        initialCap = bound(initialCap, 100, type(uint128).max);
        spendAmount = bound(spendAmount, 1, initialCap);
        newCap = bound(newCap, 1, type(uint128).max);

        vault.setSpendingCap(token, initialCap);

        vm.prank(protocol);
        vault.recordSpending(token, spendAmount);

        // Set new cap - should reset spending
        vault.setSpendingCap(token, newCap);

        // Remaining should equal new cap (spending reset)
        assertEq(vault.getRemainingSpendingCap(token), newCap);
    }

    /**
     * @notice Fuzz test: Zero amount spending should revert
     * @param cap Any valid cap
     */
    function testFuzz_ZeroAmountReverts(uint256 cap) public {
        cap = bound(cap, 1, type(uint128).max);
        vault.setSpendingCap(token, cap);

        vm.prank(protocol);
        vm.expectRevert("IntentVault: amount must be greater than zero");
        vault.recordSpending(token, 0);
    }
}
