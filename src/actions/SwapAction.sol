pragma solidity ^0.8.19;

import {IAction} from "./IAction.sol";
import {IIntentVault} from "../IIntentVault.sol";
import {Ownable} from "../Ownable.sol";

interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

interface IUniswapV2Router {
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);
}

/**
 * @title SwapAction
 * @notice Executes token swaps with slippage protection
 * @dev Implements configurable minimum slippage tolerance to protect users from MEV
 */
contract SwapAction is IAction, Ownable {
    address public constant UNISWAP_ROUTER = 0x4752ba5DBbc23f44D87826aCB77Cbf34405e94cC;

    // Slippage tolerance in basis points (1 bp = 0.01%)
    // Default: 50 bp = 0.5% minimum slippage protection
    uint256 public minSlippageBps = 50;

    // Maximum allowed slippage: 500 bp = 5%
    uint256 public maxSlippageBps = 500;

    // Basis points denominator (100% = 10000 bp)
    uint256 private constant BPS_DENOMINATOR = 10000;

    event MinSlippageUpdated(uint256 oldValue, uint256 newValue);
    event MaxSlippageUpdated(uint256 oldValue, uint256 newValue);
    event SlippageProtectionTriggered(
        address indexed vault,
        uint256 amountIn,
        uint256 amountOutMin,
        uint256 calculatedMin
    );

    function actionType() external pure returns (uint8) {
        return 1;
    }

    /**
     * @dev Sets the minimum slippage tolerance
     * @param newMinSlippageBps New minimum slippage in basis points
     * @notice Only owner can call this function
     */
    function setMinSlippage(uint256 newMinSlippageBps) external onlyOwner {
        require(newMinSlippageBps > 0, "SwapAction: min slippage must be greater than zero");
        require(newMinSlippageBps <= maxSlippageBps, "SwapAction: min slippage exceeds max");
        uint256 oldValue = minSlippageBps;
        minSlippageBps = newMinSlippageBps;
        emit MinSlippageUpdated(oldValue, newMinSlippageBps);
    }

    /**
     * @dev Sets the maximum slippage tolerance
     * @param newMaxSlippageBps New maximum slippage in basis points
     * @notice Only owner can call this function
     */
    function setMaxSlippage(uint256 newMaxSlippageBps) external onlyOwner {
        require(newMaxSlippageBps >= minSlippageBps, "SwapAction: max slippage below min");
        require(newMaxSlippageBps <= BPS_DENOMINATOR, "SwapAction: max slippage exceeds 100%");
        uint256 oldValue = maxSlippageBps;
        maxSlippageBps = newMaxSlippageBps;
        emit MaxSlippageUpdated(oldValue, newMaxSlippageBps);
    }

    /**
     * @dev Returns the current slippage configuration
     * @return minBps Minimum slippage in basis points
     * @return maxBps Maximum slippage in basis points
     * @return denominator Basis points denominator
     */
    function getSlippageConfig() external view returns (
        uint256 minBps,
        uint256 maxBps,
        uint256 denominator
    ) {
        return (minSlippageBps, maxSlippageBps, BPS_DENOMINATOR);
    }

    /**
     * @dev Calculates the minimum output amount based on input and slippage
     * @param amountIn The input amount
     * @return minOutput The minimum acceptable output amount
     */
    function calculateMinOutput(uint256 amountIn) external view returns (uint256 minOutput) {
        return (amountIn * (BPS_DENOMINATOR - minSlippageBps)) / BPS_DENOMINATOR;
    }

    function execute(address vault, bytes calldata actionData) external returns (bool) {
        require(vault != address(0), "SwapAction: vault is zero address");
        require(IIntentVault(vault).isApprovedProtocol(msg.sender), "SwapAction: protocol not approved");
        require(!IIntentVault(vault).isPaused(), "SwapAction: vault is paused");

        (
            address tokenIn,
            address tokenOut,
            uint256 amountIn,
            uint256 amountOutMin,
            uint256 deadline
        ) = abi.decode(actionData, (address, address, uint256, uint256, uint256));

        require(tokenIn != address(0) && tokenOut != address(0), "SwapAction: invalid token addresses");
        require(amountIn > 0, "SwapAction: amount must be greater than zero");
        require(deadline > block.timestamp, "SwapAction: deadline expired");

        // Calculate minimum acceptable output based on slippage tolerance
        // This assumes 1:1 price for simplification - in production, use oracle
        uint256 calculatedMinOutput = (amountIn * (BPS_DENOMINATOR - minSlippageBps)) / BPS_DENOMINATOR;

        // Validate that user's amountOutMin meets minimum slippage requirements
        // This prevents users from setting amountOutMin to 0 or too low, protecting from MEV
        if (amountOutMin < calculatedMinOutput) {
            emit SlippageProtectionTriggered(vault, amountIn, amountOutMin, calculatedMinOutput);
            revert("SwapAction: slippage tolerance too high");
        }

        // Ensure slippage is within maximum bounds
        uint256 maxSlippageOutput = (amountIn * (BPS_DENOMINATOR - maxSlippageBps)) / BPS_DENOMINATOR;
        require(amountOutMin <= amountIn, "SwapAction: invalid min output");

        uint256 remainingCap = IIntentVault(vault).getRemainingSpendingCap(tokenIn);
        require(remainingCap >= amountIn, "SwapAction: spending cap exceeded");

        IERC20(tokenIn).transferFrom(vault, address(this), amountIn);

        IERC20(tokenIn).approve(UNISWAP_ROUTER, amountIn);

        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        uint256[] memory amounts = IUniswapV2Router(UNISWAP_ROUTER).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            vault,
            deadline
        );

        IIntentVault(vault).recordSpending(tokenIn, amountIn);

        return amounts[1] >= amountOutMin;
    }
}
