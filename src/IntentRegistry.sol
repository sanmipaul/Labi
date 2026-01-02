// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IIntentRegistry} from "./IIntentRegistry.sol";

/**
 * @title IntentRegistry
 * @notice Registry for managing user intent flows
 * @dev Implements zero address validation to prevent locked funds and broken functionality
 *
 * Security: All address parameters are validated against zero address to ensure:
 * - Flows cannot be created for invalid addresses
 * - Flow ownership is always valid
 * - No funds can be locked in unreachable flows
 */
contract IntentRegistry is IIntentRegistry {
    uint256 private flowCounter;
    
    mapping(uint256 => IntentFlow) private flows;
    mapping(address => uint256[]) private userFlows;

    event FlowCreated(
        uint256 indexed flowId,
        address indexed user,
        uint8 triggerType,
        uint256 triggerValue
    );
    event FlowStatusUpdated(uint256 indexed flowId, bool active);
    event FlowExecuted(uint256 indexed flowId, uint256 timestamp);

    constructor() {
        flowCounter = 0;
    }

    function createFlow(
        uint8 triggerType,
        uint256 triggerValue,
        bytes calldata triggerData,
        bytes calldata conditionData,
        bytes calldata actionData
    ) external returns (uint256) {
        require(triggerType > 0 && triggerType <= 2, "Invalid trigger type");
        
        uint256 flowId = ++flowCounter;
        
        flows[flowId] = IntentFlow({
            id: flowId,
            user: msg.sender,
            triggerType: triggerType,
            triggerValue: triggerValue,
            triggerData: triggerData,
            conditionData: conditionData,
            actionData: actionData,
            active: true,
            lastExecutedAt: 0,
            executionCount: 0
        });

        userFlows[msg.sender].push(flowId);

        emit FlowCreated(flowId, msg.sender, triggerType, triggerValue);
        return flowId;
    }

    function getFlow(uint256 flowId) external view returns (IntentFlow memory) {
        require(flows[flowId].user != address(0), "Flow does not exist");
        return flows[flowId];
    }

    function getUserFlows(address user) external view returns (uint256[] memory) {
        require(user != address(0), "IntentRegistry: user address is zero");
        return userFlows[user];
    }

    function updateFlowStatus(uint256 flowId, bool active) external {
        require(flows[flowId].user == msg.sender, "Only flow owner can update");
        flows[flowId].active = active;
        emit FlowStatusUpdated(flowId, active);
    }

    function recordExecution(uint256 flowId) external {
        require(flows[flowId].user != address(0), "Flow does not exist");
        require(flows[flowId].active, "Flow is not active");
        
        flows[flowId].lastExecutedAt = block.timestamp;
        flows[flowId].executionCount++;
        
        emit FlowExecuted(flowId, block.timestamp);
    }

    function getFlowCounter() external view returns (uint256) {
        return flowCounter;
    }
}
