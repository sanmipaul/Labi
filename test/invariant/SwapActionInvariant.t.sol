// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/StdInvariant.sol";
import "../../src/actions/SwapAction.sol";

/**
 * @title SwapActionHandler
 * @notice Handler contract for SwapAction invariant testing
 */
contract SwapActionHandler is Test {
    SwapAction public swapAction;

    uint256 public ghost_minSlippage;
    uint256 public ghost_maxSlippage;
    uint256 public ghost_callCount;

    uint256 constant BPS_DENOMINATOR = 10000;

    constructor(SwapAction _swapAction) {
        swapAction = _swapAction;
        ghost_minSlippage = _swapAction.minSlippageBps();
        ghost_maxSlippage = _swapAction.maxSlippageBps();
    }

    function setMinSlippage(uint256 newMin) external {
        newMin = bound(newMin, 1, ghost_maxSlippage);

        try swapAction.setMinSlippage(newMin) {
            ghost_minSlippage = newMin;
            ghost_callCount++;
        } catch {}
    }

    function setMaxSlippage(uint256 newMax) external {
        newMax = bound(newMax, ghost_minSlippage, BPS_DENOMINATOR);

        try swapAction.setMaxSlippage(newMax) {
            ghost_maxSlippage = newMax;
            ghost_callCount++;
        } catch {}
    }
}

/**
 * @title SwapActionInvariantTest
 * @notice Invariant tests for SwapAction
 */
contract SwapActionInvariantTest is StdInvariant, Test {
    SwapAction public swapAction;
    SwapActionHandler public handler;

    uint256 constant BPS_DENOMINATOR = 10000;

    function setUp() public {
        swapAction = new SwapAction();
        handler = new SwapActionHandler(swapAction);

        targetContract(address(handler));
    }

    /**
     * @notice Invariant: Min slippage <= Max slippage
     */
    function invariant_MinLessOrEqualMax() public {
        uint256 minSlippage = swapAction.minSlippageBps();
        uint256 maxSlippage = swapAction.maxSlippageBps();

        assertLe(minSlippage, maxSlippage);
    }

    /**
     * @notice Invariant: Max slippage <= 100%
     */
    function invariant_MaxSlippageBounded() public {
        uint256 maxSlippage = swapAction.maxSlippageBps();

        assertLe(maxSlippage, BPS_DENOMINATOR);
    }

    /**
     * @notice Invariant: Min slippage > 0
     */
    function invariant_MinSlippagePositive() public {
        uint256 minSlippage = swapAction.minSlippageBps();

        assertGt(minSlippage, 0);
    }

    /**
     * @notice Invariant: Action type is always 1
     */
    function invariant_ActionTypeConstant() public {
        assertEq(swapAction.actionType(), 1);
    }

    /**
     * @notice Invariant: Slippage config is consistent
     */
    function invariant_SlippageConfigConsistent() public {
        (uint256 minBps, uint256 maxBps, uint256 denominator) = swapAction.getSlippageConfig();

        assertEq(minBps, swapAction.minSlippageBps());
        assertEq(maxBps, swapAction.maxSlippageBps());
        assertEq(denominator, BPS_DENOMINATOR);
    }

    /**
     * @notice Invariant: Ghost tracking matches contract state
     */
    function invariant_GhostTrackingAccurate() public {
        assertEq(handler.ghost_minSlippage(), swapAction.minSlippageBps());
        assertEq(handler.ghost_maxSlippage(), swapAction.maxSlippageBps());
    }
}
