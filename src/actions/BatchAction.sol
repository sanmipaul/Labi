// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAction} from "./IAction.sol";

contract BatchAction is IAction {
    function execute(address vault, bytes calldata data) external returns (bool) {
        (address[] memory dests, uint256[] memory values, bytes[] memory funcs) = abi.decode(data, (address[], uint256[], bytes[]));
        
        for (uint256 i = 0; i < dests.length; i++) {
            (bool success,) = dests[i].call{value: values[i]}(funcs[i]);
            require(success, "Batch action failed");
        }
        return true;
    }
}