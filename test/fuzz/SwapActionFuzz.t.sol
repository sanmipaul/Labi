// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/actions/SwapAction.sol";

/**
 * @title SwapActionFuzzTest
 * @notice Fuzz tests for SwapAction amount validations and slippage
 */
contract SwapActionFuzzTest is Test {
    SwapAction public swapAction;

    uint256 constant BPS_DENOMINATOR = 10000;

    function setUp() public {
        swapAction = new SwapAction();
    }

    /**
     * @notice Fuzz test: Min output calculation is correct
     * @param amountIn Input amount
     */
    function testFuzz_MinOutputCalculation(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, type(uint128).max);

        uint256 minSlippage = swapAction.minSlippageBps();
        uint256 expectedOutput = (amountIn * (BPS_DENOMINATOR - minSlippage)) / BPS_DENOMINATOR;

        uint256 actualOutput = swapAction.calculateMinOutput(amountIn);

        assertEq(actualOutput, expectedOutput);
    }

    /**
     * @notice Fuzz test: Slippage config returns correct values
     */
    function testFuzz_SlippageConfigConsistency() public {
        (uint256 minBps, uint256 maxBps, uint256 denominator) = swapAction.getSlippageConfig();

        assertEq(minBps, swapAction.minSlippageBps());
        assertEq(maxBps, swapAction.maxSlippageBps());
        assertEq(denominator, BPS_DENOMINATOR);
    }

    /**
     * @notice Fuzz test: Set min slippage validation
     * @param newMinSlippage New min slippage value
     */
    function testFuzz_SetMinSlippageValidation(uint256 newMinSlippage) public {
        uint256 maxSlippage = swapAction.maxSlippageBps();

        if (newMinSlippage == 0) {
            vm.expectRevert("SwapAction: min slippage must be greater than zero");
            swapAction.setMinSlippage(newMinSlippage);
        } else if (newMinSlippage > maxSlippage) {
            vm.expectRevert("SwapAction: min slippage exceeds max");
            swapAction.setMinSlippage(newMinSlippage);
        } else {
            swapAction.setMinSlippage(newMinSlippage);
            assertEq(swapAction.minSlippageBps(), newMinSlippage);
        }
    }

    /**
     * @notice Fuzz test: Set max slippage validation
     * @param newMaxSlippage New max slippage value
     */
    function testFuzz_SetMaxSlippageValidation(uint256 newMaxSlippage) public {
        uint256 minSlippage = swapAction.minSlippageBps();

        if (newMaxSlippage < minSlippage) {
            vm.expectRevert("SwapAction: max slippage below min");
            swapAction.setMaxSlippage(newMaxSlippage);
        } else if (newMaxSlippage > BPS_DENOMINATOR) {
            vm.expectRevert("SwapAction: max slippage exceeds 100%");
            swapAction.setMaxSlippage(newMaxSlippage);
        } else {
            swapAction.setMaxSlippage(newMaxSlippage);
            assertEq(swapAction.maxSlippageBps(), newMaxSlippage);
        }
    }

    /**
     * @notice Fuzz test: Slippage bounds are maintained
     * @param minSlip New min slippage
     * @param maxSlip New max slippage
     */
    function testFuzz_SlippageBoundsMaintained(uint256 minSlip, uint256 maxSlip) public {
        minSlip = bound(minSlip, 1, 1000);
        maxSlip = bound(maxSlip, minSlip, BPS_DENOMINATOR);

        // Set max first (must be >= current min)
        if (maxSlip >= swapAction.minSlippageBps()) {
            swapAction.setMaxSlippage(maxSlip);
        }

        // Set min (must be <= current max)
        if (minSlip <= swapAction.maxSlippageBps()) {
            swapAction.setMinSlippage(minSlip);
        }

        // Verify invariant: min <= max
        assertLe(swapAction.minSlippageBps(), swapAction.maxSlippageBps());
    }

    /**
     * @notice Fuzz test: Action type is always 1
     */
    function testFuzz_ActionTypeConstant() public {
        assertEq(swapAction.actionType(), 1);
    }

    /**
     * @notice Fuzz test: Min output never exceeds input
     * @param amountIn Input amount
     */
    function testFuzz_MinOutputNeverExceedsInput(uint256 amountIn) public {
        amountIn = bound(amountIn, 1, type(uint128).max);

        uint256 minOutput = swapAction.calculateMinOutput(amountIn);

        assertLe(minOutput, amountIn);
    }

    /**
     * @notice Fuzz test: Min output positive for positive input
     * @param amountIn Positive input amount
     */
    function testFuzz_MinOutputPositiveForPositiveInput(uint256 amountIn) public {
        amountIn = bound(amountIn, 100, type(uint128).max); // Min 100 to avoid rounding to 0

        uint256 minOutput = swapAction.calculateMinOutput(amountIn);

        assertGt(minOutput, 0);
    }

    /**
     * @notice Fuzz test: Slippage percentage calculation
     * @param amountIn Input amount
     * @param slippageBps Slippage in basis points
     */
    function testFuzz_SlippagePercentageCalculation(uint256 amountIn, uint256 slippageBps) public {
        amountIn = bound(amountIn, 1000, type(uint128).max);
        slippageBps = bound(slippageBps, 1, 500); // Up to 5%

        // Set the min slippage
        if (slippageBps <= swapAction.maxSlippageBps()) {
            swapAction.setMinSlippage(slippageBps);
        }

        uint256 minOutput = swapAction.calculateMinOutput(amountIn);
        uint256 slippageAmount = amountIn - minOutput;

        // Verify slippage is within expected range
        uint256 expectedSlippage = (amountIn * slippageBps) / BPS_DENOMINATOR;

        // Allow for rounding differences
        assertApproxEqAbs(slippageAmount, expectedSlippage, 1);
    }

    /**
     * @notice Fuzz test: Extreme slippage values
     * @param slippageBps Slippage value to test
     */
    function testFuzz_ExtremeSlippageValues(uint256 slippageBps) public {
        // Test with current max as upper bound
        slippageBps = bound(slippageBps, 1, BPS_DENOMINATOR);

        // First set max to allow the min
        if (slippageBps <= BPS_DENOMINATOR) {
            swapAction.setMaxSlippage(slippageBps);
        }

        // Then set min
        if (slippageBps <= swapAction.maxSlippageBps() && slippageBps > 0) {
            swapAction.setMinSlippage(slippageBps);
            assertEq(swapAction.minSlippageBps(), slippageBps);
        }
    }

    /**
     * @notice Fuzz test: Owner-only functions
     * @param caller Random caller address
     * @param newValue New slippage value
     */
    function testFuzz_OnlyOwnerCanSetSlippage(address caller, uint256 newValue) public {
        vm.assume(caller != address(this)); // This contract is the owner
        newValue = bound(newValue, 1, 500);

        vm.prank(caller);
        vm.expectRevert();
        swapAction.setMinSlippage(newValue);

        vm.prank(caller);
        vm.expectRevert();
        swapAction.setMaxSlippage(newValue);
    }

    /**
     * @notice Fuzz test: Multiple slippage updates
     * @param updates Array of slippage updates
     */
    function testFuzz_MultipleSlippageUpdates(uint256[5] memory updates) public {
        for (uint256 i = 0; i < 5; i++) {
            updates[i] = bound(updates[i], 1, 500);

            // Update min slippage (within bounds)
            if (updates[i] <= swapAction.maxSlippageBps()) {
                swapAction.setMinSlippage(updates[i]);
                assertEq(swapAction.minSlippageBps(), updates[i]);
            }
        }

        // Invariant: min <= max always holds
        assertLe(swapAction.minSlippageBps(), swapAction.maxSlippageBps());
    }

    /**
     * @notice Fuzz test: Calculate min output with varying slippage
     * @param amountIn Input amount
     * @param slippageBps Slippage to set
     */
    function testFuzz_CalculateMinOutputWithVaryingSlippage(
        uint256 amountIn,
        uint256 slippageBps
    ) public {
        amountIn = bound(amountIn, 1000, type(uint128).max);
        slippageBps = bound(slippageBps, 1, 500);

        // Set slippage
        if (slippageBps <= swapAction.maxSlippageBps()) {
            swapAction.setMinSlippage(slippageBps);
        }

        uint256 minOutput = swapAction.calculateMinOutput(amountIn);

        // Verify min output is calculated correctly
        uint256 expected = (amountIn * (BPS_DENOMINATOR - swapAction.minSlippageBps())) / BPS_DENOMINATOR;
        assertEq(minOutput, expected);
    }
}
