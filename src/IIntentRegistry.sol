pragma solidity ^0.8.19;

interface IIntentRegistry {
    struct IntentFlow {
        uint256 id;
        address user;
        uint8 triggerType;
        uint256 triggerValue;
        bytes triggerData;
        bytes conditionData;
        bytes actionData;
        bool active;
        uint256 lastExecutedAt;
        uint256 executionCount;
    }

    function createFlow(
        uint8 triggerType,
        uint256 triggerValue,
        bytes calldata triggerData,
        bytes calldata conditionData,
        bytes calldata actionData
    ) external returns (uint256);

    function getFlow(uint256 flowId) external view returns (IntentFlow memory);
    function getUserFlows(address user) external view returns (uint256[] memory);
    function updateFlowStatus(uint256 flowId, bool active) external;
    function recordExecution(uint256 flowId) external;
}
