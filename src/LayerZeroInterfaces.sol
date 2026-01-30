// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ILayerZeroEndpointV2} from "lib/LayerZero-v2/contracts/interfaces/ILayerZeroEndpointV2.sol";
import {MessagingParams, MessagingReceipt} from "lib/LayerZero-v2/contracts/interfaces/IMessaging.sol";

interface ILayerZeroReceiver {
    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable;
}

struct Origin {
    uint32 srcEid;
    bytes32 sender;
    uint64 nonce;
}