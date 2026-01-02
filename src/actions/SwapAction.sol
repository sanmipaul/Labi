pragma solidity ^0.8.19;

import {IAction} from "./IAction.sol";
import {IIntentVault} from "../IIntentVault.sol";
import {ReentrancyGuard} from "../ReentrancyGuard.sol";

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
 * @notice Executes token swaps on Uniswap V2
 * @dev Implements reentrancy protection for secure token swap execution
 *
 * Security Considerations:
 * - Protected against reentrancy attacks via ReentrancyGuard
 * - Follows checks-effects-interactions pattern
 * - All external calls are guarded by nonReentrant modifier
 * - Comprehensive input validation before any state changes
 */
contract SwapAction is IAction, ReentrancyGuard {
    address public constant UNISWAP_ROUTER = 0x4752ba5DBbc23f44D87826aCB77Cbf34405e94cC;

    event SwapExecuted(
        address indexed vault,
        address indexed tokenIn,
        address indexed tokenOut,
        uint256 amountIn,
        uint256 amountOut
    );

    /**
     * @dev Returns the action type identifier
     * @return uint8 The action type (1 for swap actions)
     */
    function actionType() external pure returns (uint8) {
        return 1;
    }

    /**
     * @dev Executes a token swap with reentrancy protection
     * @param vault The address of the user's intent vault
     * @param actionData Encoded swap parameters (tokenIn, tokenOut, amountIn, amountOutMin, deadline)
     * @return bool True if the swap was successful
     * @notice This function is protected against reentrancy attacks
     */
    function execute(address vault, bytes calldata actionData) external nonReentrant returns (bool) {
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
        require(tokenIn != tokenOut, "SwapAction: tokens must be different");
        require(amountIn > 0, "SwapAction: amount must be greater than zero");
        require(amountOutMin > 0, "SwapAction: minimum output must be greater than zero");
        require(deadline > block.timestamp, "SwapAction: deadline expired");

        uint256 remainingCap = IIntentVault(vault).getRemainingSpendingCap(tokenIn);
        require(remainingCap >= amountIn, "SwapAction: spending cap exceeded");

        // External call 1: Transfer tokens from vault to this contract
        // Protected by nonReentrant modifier
        bool transferSuccess = IERC20(tokenIn).transferFrom(vault, address(this), amountIn);
        require(transferSuccess, "SwapAction: token transfer failed");

        // Approve Uniswap router to spend tokens
        bool approveSuccess = IERC20(tokenIn).approve(UNISWAP_ROUTER, amountIn);
        require(approveSuccess, "SwapAction: token approval failed");

        // Prepare swap path
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;

        // External call 2: Execute swap on Uniswap
        // Protected by nonReentrant modifier
        uint256[] memory amounts = IUniswapV2Router(UNISWAP_ROUTER).swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            path,
            vault,
            deadline
        );

        // External call 3: Record spending in vault
        // Protected by nonReentrant modifier
        IIntentVault(vault).recordSpending(tokenIn, amountIn);

        // Emit event for successful swap
        emit SwapExecuted(vault, tokenIn, tokenOut, amountIn, amounts[1]);

        return amounts[1] >= amountOutMin;
    }
}
