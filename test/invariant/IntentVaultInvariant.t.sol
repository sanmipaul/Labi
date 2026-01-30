// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../src/IntentVault.sol";

/**
 * @title IntentVaultHandler
 * @notice Handler contract for IntentVault invariant testing
 */
contract IntentVaultHandler is Test {
    IntentVault public vault;
    address public token;
    address public protocol;

    uint256 public ghost_totalSpent;
    uint256 public ghost_spendingCap;
    uint256 public ghost_callCount;

    constructor(IntentVault _vault, address _token, address _protocol) {
        vault = _vault;
        token = _token;
        protocol = _protocol;
    }

    function setSpendingCap(uint256 cap) external {
        cap = bound(cap, 1, type(uint128).max);

        vault.setSpendingCap(token, cap);
        ghost_spendingCap = cap;
        ghost_totalSpent = 0; // Reset on new cap
        ghost_callCount++;
    }

    function recordSpending(uint256 amount) external {
        amount = bound(amount, 1, ghost_spendingCap > ghost_totalSpent ? ghost_spendingCap - ghost_totalSpent : 1);

        if (ghost_spendingCap == 0) return;
        if (ghost_totalSpent + amount > ghost_spendingCap) return;

        vm.prank(protocol);
        try vault.recordSpending(token, amount) {
            ghost_totalSpent += amount;
            ghost_callCount++;
        } catch {}
    }

    function pause() external {
        try vault.pause() {
            ghost_callCount++;
        } catch {}
    }

    function unpause() external {
        try vault.unpause() {
            ghost_callCount++;
        } catch {}
    }
}

/**
 * @title IntentVaultInvariantTest
 * @notice Invariant tests for IntentVault
 */
contract IntentVaultInvariantTest is StdInvariant, Test {
    IntentVault public vault;
    IntentVaultHandler public handler;
    address public token;
    address public protocol;

    function setUp() public {
        token = address(0x1111);
        protocol = address(0x2222);

        vault = new IntentVault(address(0x1234));
        vault.approveProtocol(protocol);
        vault.setSpendingCap(token, 1000e18);

        handler = new IntentVaultHandler(vault, token, protocol);

        targetContract(address(handler));
    }

    /**
     * @notice Invariant: Spent amount never exceeds cap
     */
    function invariant_SpentNeverExceedsCap() public {
        uint256 cap = vault.getSpendingCap(token);
        uint256 remaining = vault.getRemainingSpendingCap(token);

        // If there's a cap set, remaining should never be negative (always <= cap)
        if (cap > 0) {
            assertLe(cap - remaining, cap);
        }
    }

    /**
     * @notice Invariant: Remaining cap is always valid
     */
    function invariant_RemainingCapValid() public {
        uint256 cap = vault.getSpendingCap(token);
        uint256 remaining = vault.getRemainingSpendingCap(token);

        assertLe(remaining, cap);
    }

    /**
     * @notice Invariant: Ghost tracking matches contract state
     */
    function invariant_GhostTrackingAccurate() public {
        if (handler.ghost_spendingCap() > 0) {
            uint256 remaining = vault.getRemainingSpendingCap(token);
            uint256 expectedRemaining = handler.ghost_spendingCap() - handler.ghost_totalSpent();

            assertEq(remaining, expectedRemaining);
        }
    }
}
