// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IFlowSimulator.sol";
import "./FlowSimulator.sol";
import "./SimulationEvents.sol";

/**
 * @title DryRunSimulator
 * @notice Provides step-by-step dry run execution for flow testing
 * @dev Breaks down simulation into individual steps for debugging
 */
contract DryRunSimulator {
    // ============ Structs ============

    struct DryRunStep {
        string name;
        bool success;
        string message;
        uint256 gasUsed;
        bytes returnData;
    }

    struct DryRunResult {
        bytes32 runId;
        bool overallSuccess;
        DryRunStep[] steps;
        uint256 totalGas;
        uint256 timestamp;
        string summary;
    }

    struct DryRunConfig {
        bool stopOnFailure;
        bool recordGas;
        bool verbose;
        uint256 maxSteps;
    }

    // ============ State ============

    FlowSimulator public simulator;
    address public owner;

    // Dry run history
    mapping(bytes32 => DryRunResult) public dryRunHistory;
    mapping(address => bytes32[]) public userDryRuns;

    uint256 public constant MAX_STEPS = 20;
    uint256 public constant DEFAULT_MAX_STEPS = 10;

    // ============ Events ============

    event DryRunStarted(
        bytes32 indexed runId,
        address indexed user,
        uint256 stepCount
    );

    event DryRunStepCompleted(
        bytes32 indexed runId,
        uint256 indexed stepIndex,
        string stepName,
        bool success,
        uint256 gasUsed
    );

    event DryRunCompleted(
        bytes32 indexed runId,
        bool overallSuccess,
        uint256 totalSteps,
        uint256 successfulSteps,
        uint256 totalGas
    );

    // ============ Modifiers ============

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    // ============ Constructor ============

    constructor(address _simulator) {
        owner = msg.sender;
        simulator = FlowSimulator(_simulator);
    }

    // ============ Admin Functions ============

    function setSimulator(address _simulator) external onlyOwner {
        require(_simulator != address(0), "Invalid simulator");
        simulator = FlowSimulator(_simulator);
    }

    // ============ Dry Run Functions ============

    /**
     * @notice Execute a full dry run with default configuration
     * @param params Flow parameters to test
     * @return result Complete dry run result
     */
    function dryRun(IFlowSimulator.FlowParams calldata params)
        external
        returns (DryRunResult memory result)
    {
        DryRunConfig memory config = DryRunConfig({
            stopOnFailure: false,
            recordGas: true,
            verbose: true,
            maxSteps: DEFAULT_MAX_STEPS
        });

        return dryRunWithConfig(params, config);
    }

    /**
     * @notice Execute a dry run with custom configuration
     * @param params Flow parameters to test
     * @param config Dry run configuration
     * @return result Complete dry run result
     */
    function dryRunWithConfig(
        IFlowSimulator.FlowParams calldata params,
        DryRunConfig memory config
    ) public returns (DryRunResult memory result) {
        bytes32 runId = SimulationEvents.generateRunId(
            params.user,
            1,
            block.number
        );

        result.runId = runId;
        result.timestamp = block.timestamp;

        // Initialize steps array
        DryRunStep[] memory steps = new DryRunStep[](config.maxSteps);
        uint256 stepIndex = 0;
        uint256 successfulSteps = 0;
        bool continueExecution = true;

        emit DryRunStarted(runId, params.user, config.maxSteps);

        // Step 1: Parameter Validation
        if (continueExecution && stepIndex < config.maxSteps) {
            uint256 gasStart = gasleft();

            (bool success, string memory message) = _runParameterValidation(params);

            steps[stepIndex] = DryRunStep({
                name: "Parameter Validation",
                success: success,
                message: message,
                gasUsed: config.recordGas ? gasStart - gasleft() : 0,
                returnData: ""
            });

            emit DryRunStepCompleted(runId, stepIndex, "Parameter Validation", success, steps[stepIndex].gasUsed);

            if (success) successfulSteps++;
            if (!success && config.stopOnFailure) continueExecution = false;
            stepIndex++;
        }

        // Step 2: Trigger Validation
        if (continueExecution && stepIndex < config.maxSteps) {
            uint256 gasStart = gasleft();

            (bool success, string memory message) = _runTriggerValidation(params);

            steps[stepIndex] = DryRunStep({
                name: "Trigger Validation",
                success: success,
                message: message,
                gasUsed: config.recordGas ? gasStart - gasleft() : 0,
                returnData: ""
            });

            emit DryRunStepCompleted(runId, stepIndex, "Trigger Validation", success, steps[stepIndex].gasUsed);

            if (success) successfulSteps++;
            if (!success && config.stopOnFailure) continueExecution = false;
            stepIndex++;
        }

        // Step 3: Action Validation
        if (continueExecution && stepIndex < config.maxSteps) {
            uint256 gasStart = gasleft();

            (bool success, string memory message) = _runActionValidation(params);

            steps[stepIndex] = DryRunStep({
                name: "Action Validation",
                success: success,
                message: message,
                gasUsed: config.recordGas ? gasStart - gasleft() : 0,
                returnData: ""
            });

            emit DryRunStepCompleted(runId, stepIndex, "Action Validation", success, steps[stepIndex].gasUsed);

            if (success) successfulSteps++;
            if (!success && config.stopOnFailure) continueExecution = false;
            stepIndex++;
        }

        // Step 4: Gas Estimation
        if (continueExecution && stepIndex < config.maxSteps) {
            uint256 gasStart = gasleft();

            (bool success, string memory message, bytes memory data) = _runGasEstimation(params);

            steps[stepIndex] = DryRunStep({
                name: "Gas Estimation",
                success: success,
                message: message,
                gasUsed: config.recordGas ? gasStart - gasleft() : 0,
                returnData: data
            });

            emit DryRunStepCompleted(runId, stepIndex, "Gas Estimation", success, steps[stepIndex].gasUsed);

            if (success) successfulSteps++;
            if (!success && config.stopOnFailure) continueExecution = false;
            stepIndex++;
        }

        // Step 5: Balance Check
        if (continueExecution && stepIndex < config.maxSteps) {
            uint256 gasStart = gasleft();

            (bool success, string memory message) = _runBalanceCheck(params);

            steps[stepIndex] = DryRunStep({
                name: "Balance Check",
                success: success,
                message: message,
                gasUsed: config.recordGas ? gasStart - gasleft() : 0,
                returnData: ""
            });

            emit DryRunStepCompleted(runId, stepIndex, "Balance Check", success, steps[stepIndex].gasUsed);

            if (success) successfulSteps++;
            if (!success && config.stopOnFailure) continueExecution = false;
            stepIndex++;
        }

        // Step 6: Trigger Simulation
        if (continueExecution && stepIndex < config.maxSteps) {
            uint256 gasStart = gasleft();

            (bool success, string memory message) = _runTriggerSimulation(params);

            steps[stepIndex] = DryRunStep({
                name: "Trigger Simulation",
                success: success,
                message: message,
                gasUsed: config.recordGas ? gasStart - gasleft() : 0,
                returnData: ""
            });

            emit DryRunStepCompleted(runId, stepIndex, "Trigger Simulation", success, steps[stepIndex].gasUsed);

            if (success) successfulSteps++;
            if (!success && config.stopOnFailure) continueExecution = false;
            stepIndex++;
        }

        // Step 7: Action Simulation
        if (continueExecution && stepIndex < config.maxSteps) {
            uint256 gasStart = gasleft();

            (bool success, string memory message, bytes memory data) = _runActionSimulation(params);

            steps[stepIndex] = DryRunStep({
                name: "Action Simulation",
                success: success,
                message: message,
                gasUsed: config.recordGas ? gasStart - gasleft() : 0,
                returnData: data
            });

            emit DryRunStepCompleted(runId, stepIndex, "Action Simulation", success, steps[stepIndex].gasUsed);

            if (success) successfulSteps++;
            stepIndex++;
        }

        // Trim steps array
        result.steps = new DryRunStep[](stepIndex);
        for (uint256 i = 0; i < stepIndex; i++) {
            result.steps[i] = steps[i];
            result.totalGas += steps[i].gasUsed;
        }

        result.overallSuccess = successfulSteps == stepIndex;
        result.summary = _generateSummary(stepIndex, successfulSteps);

        // Store result
        dryRunHistory[runId] = result;
        userDryRuns[params.user].push(runId);

        emit DryRunCompleted(runId, result.overallSuccess, stepIndex, successfulSteps, result.totalGas);
    }

    /**
     * @notice Run multiple dry runs in batch
     * @param paramsArray Array of flow parameters
     * @return results Array of dry run results
     */
    function batchDryRun(IFlowSimulator.FlowParams[] calldata paramsArray)
        external
        returns (DryRunResult[] memory results)
    {
        results = new DryRunResult[](paramsArray.length);

        for (uint256 i = 0; i < paramsArray.length; i++) {
            results[i] = this.dryRun(paramsArray[i]);
        }
    }

    // ============ Query Functions ============

    /**
     * @notice Get dry run result by ID
     * @param runId Dry run identifier
     * @return result Stored dry run result
     */
    function getDryRunResult(bytes32 runId)
        external
        view
        returns (DryRunResult memory result)
    {
        return dryRunHistory[runId];
    }

    /**
     * @notice Get user's dry run history
     * @param user User address
     * @return runIds Array of dry run IDs
     */
    function getUserDryRuns(address user)
        external
        view
        returns (bytes32[] memory runIds)
    {
        return userDryRuns[user];
    }

    // ============ Internal Step Functions ============

    function _runParameterValidation(IFlowSimulator.FlowParams calldata params)
        internal
        view
        returns (bool success, string memory message)
    {
        IFlowSimulator.ValidationResult memory result = simulator.validateFlow(params);

        if (result.isValid) {
            return (true, "All parameters valid");
        }

        return (false, result.errors.length > 0 ? result.errors[0] : "Validation failed");
    }

    function _runTriggerValidation(IFlowSimulator.FlowParams calldata params)
        internal
        view
        returns (bool success, string memory message)
    {
        return simulator.validateTrigger(params.triggerType, params.triggerData);
    }

    function _runActionValidation(IFlowSimulator.FlowParams calldata params)
        internal
        view
        returns (bool success, string memory message)
    {
        return simulator.validateAction(params.actionType, params.actionData);
    }

    function _runGasEstimation(IFlowSimulator.FlowParams calldata params)
        internal
        view
        returns (bool success, string memory message, bytes memory data)
    {
        try simulator.estimateGas(params) returns (IFlowSimulator.GasBreakdown memory breakdown) {
            data = abi.encode(breakdown.totalGas);
            return (true, string(abi.encodePacked("Estimated gas: ", _uint2str(breakdown.totalGas))), data);
        } catch Error(string memory reason) {
            return (false, reason, "");
        } catch {
            return (false, "Gas estimation failed", "");
        }
    }

    function _runBalanceCheck(IFlowSimulator.FlowParams calldata params)
        internal
        view
        returns (bool success, string memory message)
    {
        // For swap/transfer actions, check if mock balances are set
        if (params.actionType == 1 || params.actionType == 2) {
            if (params.actionData.length >= 96) {
                (address token,, uint256 amount) = abi.decode(
                    params.actionData,
                    (address, address, uint256)
                );

                uint256 balance = simulator.mockBalances(token, params.user);
                if (balance == 0) {
                    return (true, "No mock balance set - skipping check");
                }

                if (balance >= amount) {
                    return (true, "Sufficient balance");
                }

                return (false, "Insufficient balance");
            }
        }

        return (true, "Balance check not applicable");
    }

    function _runTriggerSimulation(IFlowSimulator.FlowParams calldata params)
        internal
        view
        returns (bool success, string memory message)
    {
        if (!simulator.isTriggerSupported(params.triggerType)) {
            return (false, "Trigger type not supported");
        }

        return (true, "Trigger would be ready for evaluation");
    }

    function _runActionSimulation(IFlowSimulator.FlowParams calldata params)
        internal
        view
        returns (bool success, string memory message, bytes memory data)
    {
        if (!simulator.isActionSupported(params.actionType)) {
            return (false, "Action type not supported", "");
        }

        return (true, "Action simulation passed", "");
    }

    function _generateSummary(uint256 totalSteps, uint256 successfulSteps)
        internal
        pure
        returns (string memory)
    {
        if (successfulSteps == totalSteps) {
            return "All steps passed - flow ready for creation";
        } else if (successfulSteps == 0) {
            return "All steps failed - review configuration";
        } else {
            return "Partial success - some steps failed";
        }
    }

    function _uint2str(uint256 _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint256 j = _i;
        uint256 len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint256 k = len;
        while (_i != 0) {
            k = k - 1;
            uint8 temp = (48 + uint8(_i - _i / 10 * 10));
            bytes1 b1 = bytes1(temp);
            bstr[k] = b1;
            _i /= 10;
        }
        return string(bstr);
    }
}
