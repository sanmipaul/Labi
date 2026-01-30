// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IFlowSimulator.sol";

/**
 * @title SimulationEvents
 * @notice Events library for flow simulation system
 */
library SimulationEvents {
    // ============ Simulation Events ============

    /// @notice Emitted when a single flow simulation is executed
    event FlowSimulated(
        address indexed user,
        bytes32 indexed paramsHash,
        IFlowSimulator.SimulationStatus status,
        bool wouldSucceed,
        uint256 estimatedGas,
        uint256 estimatedCost,
        uint256 timestamp
    );

    /// @notice Emitted when a batch simulation is executed
    event BatchFlowSimulated(
        address indexed user,
        uint256 indexed batchId,
        uint256 flowCount,
        uint256 successCount,
        uint256 totalGas,
        uint256 timestamp
    );

    /// @notice Emitted when simulation with custom state is executed
    event StatefulSimulationExecuted(
        address indexed user,
        bytes32 indexed paramsHash,
        bytes32 stateHash,
        bool wouldSucceed,
        uint256 timestamp
    );

    // ============ Validation Events ============

    /// @notice Emitted when flow parameters are validated
    event FlowValidated(
        address indexed user,
        bytes32 indexed paramsHash,
        bool isValid,
        uint256 warningCount,
        uint256 errorCount,
        uint256 timestamp
    );

    /// @notice Emitted when trigger validation is performed
    event TriggerValidated(
        address indexed user,
        uint8 indexed triggerType,
        bool isValid,
        string message
    );

    /// @notice Emitted when action validation is performed
    event ActionValidated(
        address indexed user,
        uint8 indexed actionType,
        bool isValid,
        string message
    );

    // ============ Gas Estimation Events ============

    /// @notice Emitted when gas estimation is completed
    event GasEstimated(
        address indexed user,
        bytes32 indexed paramsHash,
        uint256 triggerGas,
        uint256 conditionGas,
        uint256 actionGas,
        uint256 overheadGas,
        uint256 totalGas
    );

    /// @notice Emitted when cost estimation is completed
    event CostEstimated(
        address indexed user,
        bytes32 indexed paramsHash,
        uint256 estimatedCost,
        uint256 gasPrice,
        uint256 timestamp
    );

    // ============ Fork Simulation Events ============

    /// @notice Emitted when a fork simulation is initiated
    event ForkSimulationStarted(
        address indexed user,
        bytes32 indexed forkId,
        uint256 blockNumber,
        uint256 timestamp
    );

    /// @notice Emitted when a fork simulation is completed
    event ForkSimulationCompleted(
        address indexed user,
        bytes32 indexed forkId,
        bool success,
        uint256 gasUsed,
        uint256 timestamp
    );

    /// @notice Emitted when fork simulation fails
    event ForkSimulationFailed(
        address indexed user,
        bytes32 indexed forkId,
        string reason,
        uint256 timestamp
    );

    // ============ Dry Run Events ============

    /// @notice Emitted when a dry run is initiated
    event DryRunStarted(
        address indexed user,
        bytes32 indexed runId,
        uint256 flowCount,
        uint256 timestamp
    );

    /// @notice Emitted when a dry run step is completed
    event DryRunStepCompleted(
        bytes32 indexed runId,
        uint256 indexed stepIndex,
        string stepName,
        bool success,
        uint256 gasUsed
    );

    /// @notice Emitted when a dry run is completed
    event DryRunCompleted(
        bytes32 indexed runId,
        bool overallSuccess,
        uint256 totalSteps,
        uint256 successfulSteps,
        uint256 totalGas,
        uint256 timestamp
    );

    // ============ Error Events ============

    /// @notice Emitted when simulation encounters an error
    event SimulationError(
        address indexed user,
        bytes32 indexed paramsHash,
        string errorType,
        string message,
        uint256 timestamp
    );

    /// @notice Emitted when validation encounters an error
    event ValidationError(
        address indexed user,
        bytes32 indexed paramsHash,
        string errorType,
        string message,
        uint256 timestamp
    );

    // ============ Configuration Events ============

    /// @notice Emitted when a trigger contract is registered
    event TriggerContractRegistered(
        uint8 indexed triggerType,
        address indexed contractAddress,
        uint256 timestamp
    );

    /// @notice Emitted when an action contract is registered
    event ActionContractRegistered(
        uint8 indexed actionType,
        address indexed contractAddress,
        uint256 timestamp
    );

    /// @notice Emitted when gas oracle is updated
    event GasOracleUpdated(
        address indexed oldOracle,
        address indexed newOracle,
        uint256 timestamp
    );

    // ============ Helper Functions ============

    /**
     * @notice Compute hash of flow parameters for event correlation
     * @param params Flow parameters to hash
     * @return paramsHash Hash of the parameters
     */
    function hashFlowParams(IFlowSimulator.FlowParams memory params) internal pure returns (bytes32) {
        return keccak256(abi.encode(
            params.user,
            params.triggerType,
            params.actionType,
            params.triggerValue,
            params.triggerData,
            params.conditionData,
            params.actionData,
            params.dstEid
        ));
    }

    /**
     * @notice Generate unique batch ID
     * @param user User address
     * @param flowCount Number of flows
     * @param timestamp Timestamp of batch
     * @return batchId Unique batch identifier
     */
    function generateBatchId(
        address user,
        uint256 flowCount,
        uint256 timestamp
    ) internal pure returns (uint256) {
        return uint256(keccak256(abi.encode(user, flowCount, timestamp)));
    }

    /**
     * @notice Generate unique run ID for dry runs
     * @param user User address
     * @param flowCount Number of flows
     * @param blockNumber Current block number
     * @return runId Unique run identifier
     */
    function generateRunId(
        address user,
        uint256 flowCount,
        uint256 blockNumber
    ) internal pure returns (bytes32) {
        return keccak256(abi.encode(user, flowCount, blockNumber, block.timestamp));
    }
}
