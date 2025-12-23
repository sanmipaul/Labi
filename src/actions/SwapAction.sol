pragma solidity ^0.8.19;

import {IAction} from "./IAction.sol";
import {IIntentVault} from "../IIntentVault.sol";

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

contract SwapAction is IAction {
    address public constant UNISWAP_ROUTER = 0x4752ba5DBbc23f44D87826aCB77Cbf34405e94cC;

    function actionType() external pure returns (uint8) {
        return 1;
    }

    function execute(address vault, bytes calldata actionData) external returns (bool) {
        require(vault != address(0), "Invalid vault");
        require(IIntentVault(vault).isApprovedProtocol(msg.sender), "Protocol not approved");
        require(!IIntentVault(vault).isPaused(), "Vault is paused");

        (
            address tokenIn,
            address tokenOut,
            uint256 amountIn,
            uint256 amountOutMin,
            uint256 deadline
        ) = abi.decode(actionData, (address, address, uint256, uint256, uint256));

        require(tokenIn != address(0) && tokenOut != address(0), "Invalid tokens");
        require(amountIn > 0, "Invalid amount");
        require(deadline > block.timestamp, "Deadline expired");

        uint256 remainingCap = IIntentVault(vault).getRemainingSpendingCap(tokenIn);
        require(remainingCap >= amountIn, "Spending cap exceeded");

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
