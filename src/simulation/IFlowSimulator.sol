// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

/**
 * @title IFlowSimulator
 * @notice Interface for pre-creation flow simulation
 * @dev Allows users to test flows before deploying on-chain
 */
interface IFlowSimulator {
    /// @notice Simulation result status
    enum SimulationStatus {
        Success,
        TriggerInvalid,
        ActionInvalid,
        InsufficientBalance,
        ConditionNotMet,
        GasEstimationFailed,
        ExecutionReverted,
        ValidationFailed
    }

    /// @notice Detailed simulation result
    struct SimulationResult {
        SimulationStatus status;
        bool wouldSucceed;
        string message;
        uint256 estimatedGas;
        uint256 estimatedCost;
        bytes returnData;
        uint256 timestamp;
    }

    /// @notice Flow parameters for pre-creation simulation
    struct FlowParams {
        address user;
        uint8 triggerType;
        uint8 actionType;
        uint256 triggerValue;
        bytes triggerData;
        bytes conditionData;
        bytes actionData;
        uint32 dstEid;
    }

    /// @notice Validation result for flow parameters
    struct ValidationResult {
        bool isValid;
        bool triggerValid;
        bool actionValid;
        bool conditionValid;
        bool balancesSufficient;
        string[] warnings;
        string[] errors;
    }

    /// @notice Gas breakdown for simulation
    struct GasBreakdown {
        uint256 triggerGas;
        uint256 conditionGas;
        uint256 actionGas;
        uint256 overheadGas;
        uint256 totalGas;
    }

    // ============ Events ============

    event SimulationExecuted(
        address indexed user,
        bytes32 indexed paramsHash,
        SimulationStatus status,
        uint256 estimatedGas
    );

    event BatchSimulationExecuted(
        address indexed user,
        uint256 flowCount,
        uint256 successCount
    );

    event ValidationCompleted(
        address indexed user,
        bytes32 indexed paramsHash,
        bool isValid
    );

    // ============ Core Simulation Functions ============

    /**
     * @notice Simulate a flow before creation
     * @param params Flow parameters to simulate
     * @return result Detailed simulation result
     */
    function simulateFlow(FlowParams calldata params) external returns (SimulationResult memory result);

    /**
     * @notice Simulate a flow with custom state
     * @param params Flow parameters to simulate
     * @param mockBalances Mock token balances for simulation
     * @param mockPrices Mock prices for simulation
     * @return result Detailed simulation result
     */
    function simulateFlowWithState(
        FlowParams calldata params,
        bytes calldata mockBalances,
        bytes calldata mockPrices
    ) external returns (SimulationResult memory result);

    /**
     * @notice Batch simulate multiple flows
     * @param paramsArray Array of flow parameters
     * @return results Array of simulation results
     */
    function batchSimulate(FlowParams[] calldata paramsArray) external returns (SimulationResult[] memory results);

    // ============ Validation Functions ============

    /**
     * @notice Validate flow parameters without execution
     * @param params Flow parameters to validate
     * @return result Validation result with details
     */
    function validateFlow(FlowParams calldata params) external view returns (ValidationResult memory result);

    /**
     * @notice Check if trigger configuration is valid
     * @param triggerType Type of trigger
     * @param triggerData Encoded trigger data
     * @return isValid Whether trigger is valid
     * @return message Validation message
     */
    function validateTrigger(uint8 triggerType, bytes calldata triggerData) external view returns (bool isValid, string memory message);

    /**
     * @notice Check if action configuration is valid
     * @param actionType Type of action
     * @param actionData Encoded action data
     * @return isValid Whether action is valid
     * @return message Validation message
     */
    function validateAction(uint8 actionType, bytes calldata actionData) external view returns (bool isValid, string memory message);

    // ============ Gas Estimation Functions ============

    /**
     * @notice Estimate gas for a flow
     * @param params Flow parameters
     * @return breakdown Detailed gas breakdown
     */
    function estimateGas(FlowParams calldata params) external view returns (GasBreakdown memory breakdown);

    /**
     * @notice Estimate execution cost in native token
     * @param params Flow parameters
     * @return cost Estimated cost in wei
     */
    function estimateCost(FlowParams calldata params) external view returns (uint256 cost);

    // ============ State Queries ============

    /**
     * @notice Get supported trigger types
     * @return triggerTypes Array of supported trigger type IDs
     */
    function getSupportedTriggers() external view returns (uint8[] memory triggerTypes);

    /**
     * @notice Get supported action types
     * @return actionTypes Array of supported action type IDs
     */
    function getSupportedActions() external view returns (uint8[] memory actionTypes);

    /**
     * @notice Check if a trigger type is supported
     * @param triggerType Trigger type to check
     * @return supported Whether trigger is supported
     */
    function isTriggerSupported(uint8 triggerType) external view returns (bool supported);

    /**
     * @notice Check if an action type is supported
     * @param actionType Action type to check
     * @return supported Whether action is supported
     */
    function isActionSupported(uint8 actionType) external view returns (bool supported);
}
