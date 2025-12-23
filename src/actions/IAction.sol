pragma solidity ^0.8.19;

interface IAction {
    function execute(address vault, bytes calldata actionData) external returns (bool);
    function actionType() external pure returns (uint8);
}
