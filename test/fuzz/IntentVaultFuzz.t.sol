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

    /**
     * @notice Fuzz test: Pause state blocks spending
     * @param cap Spending cap
     * @param amount Amount to spend
     */
    function testFuzz_PauseBlocksSpending(uint256 cap, uint256 amount) public {
        cap = bound(cap, 1, type(uint128).max);
        amount = bound(amount, 1, cap);

        vault.setSpendingCap(token, cap);
        vault.pause();

        vm.prank(protocol);
        vm.expectRevert("IntentVault: vault is paused");
        vault.recordSpending(token, amount);
    }

    /**
     * @notice Fuzz test: Unpause allows spending again
     * @param cap Spending cap
     * @param amount Amount to spend
     */
    function testFuzz_UnpauseAllowsSpending(uint256 cap, uint256 amount) public {
        cap = bound(cap, 1, type(uint128).max);
        amount = bound(amount, 1, cap);

        vault.setSpendingCap(token, cap);
        vault.pause();
        vault.unpause();

        vm.prank(protocol);
        vault.recordSpending(token, amount);

        assertEq(vault.getRemainingSpendingCap(token), cap - amount);
    }

    /**
     * @notice Fuzz test: Multiple tokens have independent caps
     * @param cap1 Cap for token 1
     * @param cap2 Cap for token 2
     * @param spend1 Spend for token 1
     * @param spend2 Spend for token 2
     */
    function testFuzz_IndependentTokenCaps(
        uint256 cap1,
        uint256 cap2,
        uint256 spend1,
        uint256 spend2
    ) public {
        address token2 = address(0x3333);

        cap1 = bound(cap1, 1, type(uint128).max);
        cap2 = bound(cap2, 1, type(uint128).max);
        spend1 = bound(spend1, 1, cap1);
        spend2 = bound(spend2, 1, cap2);

        vault.setSpendingCap(token, cap1);
        vault.setSpendingCap(token2, cap2);

        vm.startPrank(protocol);
        vault.recordSpending(token, spend1);
        vault.recordSpending(token2, spend2);
        vm.stopPrank();

        // Verify independent tracking
        assertEq(vault.getRemainingSpendingCap(token), cap1 - spend1);
        assertEq(vault.getRemainingSpendingCap(token2), cap2 - spend2);
    }

    /**
     * @notice Fuzz test: Protocol approval/revocation
     * @param protocolAddr Random protocol address
     */
    function testFuzz_ProtocolApprovalRevocation(address protocolAddr) public {
        vm.assume(protocolAddr != address(0));

        vault.approveProtocol(protocolAddr);
        assertTrue(vault.isApprovedProtocol(protocolAddr));

        vault.revokeProtocol(protocolAddr);
        assertFalse(vault.isApprovedProtocol(protocolAddr));
    }
}
