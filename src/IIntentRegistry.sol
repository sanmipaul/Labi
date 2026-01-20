pragma solidity ^0.8.19;

interface IIntentRegistry {
    struct Action {
        uint8 actionType;
        bytes actionData;
    }

    struct IntentFlow {
        uint256 id;
        address user;
        uint8 triggerType;
        uint8 actionType;
        uint256 triggerValue;
        bytes triggerData;
        bytes conditionData;
        bytes actionData;
        uint32 dstEid; // Destination chain endpoint ID for cross-chain
        bool active;
        uint256 lastExecutedAt;
        uint256 executionCount;
        uint256 executionFee; // Fee per execution
    }

    function createFlow(
        uint8 triggerType,
        uint8 actionType,
        uint256 triggerValue,
        bytes calldata triggerData,
        bytes calldata conditionData,
        bytes calldata actionData,
        uint32 dstEid
    ) external returns (uint256);

    function getFlow(uint256 flowId) external view returns (IntentFlow memory);
    function getUserFlows(address user) external view returns (uint256[] memory);
    function updateFlowStatus(uint256 flowId, bool active) external;
    function recordExecution(uint256 flowId) external;
}
