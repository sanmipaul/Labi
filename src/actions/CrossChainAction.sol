// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IAction} from "./IAction.sol";
import {ILayerZeroEndpointV2} from "../LayerZeroInterfaces.sol";
import {MessagingParams} from "../LayerZeroInterfaces.sol";

contract CrossChainAction is IAction {
    ILayerZeroEndpointV2 public lzEndpoint;

    constructor(address lzEndpointAddress) {
        lzEndpoint = ILayerZeroEndpointV2(lzEndpointAddress);
    }

    function execute(address vault, bytes calldata data) external returns (bool) {
        (uint32 dstEid, bytes32 dstAddress, uint256 flowId, bytes memory actionData) = abi.decode(data, (uint32, bytes32, uint256, bytes));
        
        bytes memory message = abi.encode(flowId, actionData);
        MessagingParams memory params = MessagingParams({
            dstEid: dstEid,
            receiver: dstAddress,
            message: message,
            options: "",
            payInLzToken: false
        });

        lzEndpoint.send(params, vault);
        return true;
    }
}