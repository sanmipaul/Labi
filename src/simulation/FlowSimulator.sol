// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IFlowSimulator.sol";
import "./FlowValidator.sol";
import "./GasEstimator.sol";
import "./SimulationEvents.sol";
import "../triggers/ITrigger.sol";
import "../actions/IAction.sol";
import "../IIntentVault.sol";

/**
 * @title FlowSimulator
 * @notice Main contract for pre-creation flow simulation
 * @dev Allows users to test flows before deploying on-chain
 */
contract FlowSimulator is IFlowSimulator {
    // ============ State ============

    FlowValidator public validator;
    GasEstimator public gasEstimator;

    mapping(uint8 => address) public triggerContracts;
    mapping(uint8 => address) public actionContracts;

    address public owner;
    bool public paused;

    // Mock state for simulations
    mapping(address => mapping(address => uint256)) public mockBalances;
    mapping(address => uint256) public mockPrices;

    // Simulation stats
    uint256 public totalSimulations;
    uint256 public successfulSimulations;

    // ============ Events ============

    event SimulatorPaused(bool paused);
    event MockBalanceSet(address indexed token, address indexed account, uint256 amount);
    event MockPriceSet(address indexed token, uint256 price);

    // ============ Modifiers ============

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Simulator is paused");
        _;
    }

    // ============ Constructor ============

    constructor(address _validator, address _gasEstimator) {
        owner = msg.sender;
        validator = FlowValidator(_validator);
        gasEstimator = GasEstimator(_gasEstimator);
    }

    // ============ Admin Functions ============

    function setPaused(bool _paused) external onlyOwner {
        paused = _paused;
        emit SimulatorPaused(_paused);
    }

    function setValidator(address _validator) external onlyOwner {
        require(_validator != address(0), "Invalid validator");
        validator = FlowValidator(_validator);
    }

    function setGasEstimator(address _gasEstimator) external onlyOwner {
        require(_gasEstimator != address(0), "Invalid gas estimator");
        gasEstimator = GasEstimator(_gasEstimator);
    }

    function setTriggerContract(uint8 triggerType, address triggerContract) external onlyOwner {
        require(triggerContract != address(0), "Invalid trigger contract");
        triggerContracts[triggerType] = triggerContract;
        emit SimulationEvents.TriggerContractRegistered(triggerType, triggerContract, block.timestamp);
    }

    function setActionContract(uint8 actionType, address actionContract) external onlyOwner {
        require(actionContract != address(0), "Invalid action contract");
        actionContracts[actionType] = actionContract;
        emit SimulationEvents.ActionContractRegistered(actionType, actionContract, block.timestamp);
    }

    // ============ Mock State Functions ============

    function setMockBalance(address token, address account, uint256 amount) external {
        mockBalances[token][account] = amount;
        emit MockBalanceSet(token, account, amount);
    }

    function setMockPrice(address token, uint256 price) external {
        mockPrices[token] = price;
        emit MockPriceSet(token, price);
    }

    function clearMockState(address token, address account) external {
        delete mockBalances[token][account];
        delete mockPrices[token];
    }

    // ============ Core Simulation Functions ============

    /**
     * @notice Simulate a flow before creation
     * @param params Flow parameters to simulate
     * @return result Detailed simulation result
     */
    function simulateFlow(FlowParams calldata params)
        external
        override
        whenNotPaused
        returns (SimulationResult memory result)
    {
        totalSimulations++;
        result.timestamp = block.timestamp;

        bytes32 paramsHash = SimulationEvents.hashFlowParams(params);

        // Step 1: Validate parameters
        ValidationResult memory validation = validator.validateFlow(params);
        if (!validation.isValid) {
            result.status = SimulationStatus.ValidationFailed;
            result.wouldSucceed = false;
            result.message = validation.errors.length > 0 ? validation.errors[0] : "Validation failed";

            emit SimulationExecuted(params.user, paramsHash, result.status, 0);
            return result;
        }

        // Step 2: Estimate gas
        try gasEstimator.estimateGas(params) returns (GasBreakdown memory breakdown) {
            result.estimatedGas = breakdown.totalGas;

            try gasEstimator.estimateCost(params) returns (uint256 cost) {
                result.estimatedCost = cost;
            } catch {
                result.estimatedCost = result.estimatedGas * tx.gasprice;
            }
        } catch {
            result.status = SimulationStatus.GasEstimationFailed;
            result.wouldSucceed = false;
            result.message = "Gas estimation failed";

            emit SimulationExecuted(params.user, paramsHash, result.status, 0);
            return result;
        }

        // Step 3: Simulate trigger check
        (bool triggerValid, string memory triggerMsg) = _simulateTrigger(params);
        if (!triggerValid) {
            result.status = SimulationStatus.TriggerInvalid;
            result.wouldSucceed = false;
            result.message = triggerMsg;

            emit SimulationExecuted(params.user, paramsHash, result.status, result.estimatedGas);
            return result;
        }

        // Step 4: Simulate action execution
        (bool actionValid, string memory actionMsg, bytes memory returnData) = _simulateAction(params);
        if (!actionValid) {
            result.status = SimulationStatus.ActionInvalid;
            result.wouldSucceed = false;
            result.message = actionMsg;
            result.returnData = returnData;

            emit SimulationExecuted(params.user, paramsHash, result.status, result.estimatedGas);
            return result;
        }

        // Simulation successful
        result.status = SimulationStatus.Success;
        result.wouldSucceed = true;
        result.message = "Simulation successful - flow would execute correctly";
        result.returnData = returnData;

        successfulSimulations++;
        emit SimulationExecuted(params.user, paramsHash, result.status, result.estimatedGas);
    }

    /**
     * @notice Simulate a flow with custom state
     * @param params Flow parameters to simulate
     * @param mockBalancesData Mock token balances for simulation
     * @param mockPricesData Mock prices for simulation
     * @return result Detailed simulation result
     */
    function simulateFlowWithState(
        FlowParams calldata params,
        bytes calldata mockBalancesData,
        bytes calldata mockPricesData
    ) external override whenNotPaused returns (SimulationResult memory result) {
        // Apply mock balances
        if (mockBalancesData.length > 0) {
            _applyMockBalances(mockBalancesData);
        }

        // Apply mock prices
        if (mockPricesData.length > 0) {
            _applyMockPrices(mockPricesData);
        }

        // Run simulation
        result = this.simulateFlow(params);

        // Emit stateful simulation event
        bytes32 paramsHash = SimulationEvents.hashFlowParams(params);
        bytes32 stateHash = keccak256(abi.encode(mockBalancesData, mockPricesData));
        emit SimulationEvents.StatefulSimulationExecuted(
            params.user,
            paramsHash,
            stateHash,
            result.wouldSucceed,
            block.timestamp
        );
    }

    /**
     * @notice Batch simulate multiple flows
     * @param paramsArray Array of flow parameters
     * @return results Array of simulation results
     */
    function batchSimulate(FlowParams[] calldata paramsArray)
        external
        override
        whenNotPaused
        returns (SimulationResult[] memory results)
    {
        results = new SimulationResult[](paramsArray.length);
        uint256 successCount = 0;
        uint256 totalGas = 0;

        for (uint256 i = 0; i < paramsArray.length; i++) {
            results[i] = this.simulateFlow(paramsArray[i]);
            if (results[i].wouldSucceed) {
                successCount++;
            }
            totalGas += results[i].estimatedGas;
        }

        emit SimulationEvents.BatchFlowSimulated(
            msg.sender,
            SimulationEvents.generateBatchId(msg.sender, paramsArray.length, block.timestamp),
            paramsArray.length,
            successCount,
            totalGas,
            block.timestamp
        );
    }

    // ============ Validation Functions ============

    /**
     * @notice Validate flow parameters without execution
     * @param params Flow parameters to validate
     * @return result Validation result with details
     */
    function validateFlow(FlowParams calldata params)
        external
        view
        override
        returns (ValidationResult memory result)
    {
        return validator.validateFlow(params);
    }

    /**
     * @notice Check if trigger configuration is valid
     * @param triggerType Type of trigger
     * @param triggerData Encoded trigger data
     * @return isValid Whether trigger is valid
     * @return message Validation message
     */
    function validateTrigger(uint8 triggerType, bytes calldata triggerData)
        external
        view
        override
        returns (bool isValid, string memory message)
    {
        return validator.validateTrigger(triggerType, triggerData);
    }

    /**
     * @notice Check if action configuration is valid
     * @param actionType Type of action
     * @param actionData Encoded action data
     * @return isValid Whether action is valid
     * @return message Validation message
     */
    function validateAction(uint8 actionType, bytes calldata actionData)
        external
        view
        override
        returns (bool isValid, string memory message)
    {
        return validator.validateAction(actionType, actionData);
    }

    // ============ Gas Estimation Functions ============

    /**
     * @notice Estimate gas for a flow
     * @param params Flow parameters
     * @return breakdown Detailed gas breakdown
     */
    function estimateGas(FlowParams calldata params)
        external
        view
        override
        returns (GasBreakdown memory breakdown)
    {
        return gasEstimator.estimateGas(params);
    }

    /**
     * @notice Estimate execution cost in native token
     * @param params Flow parameters
     * @return cost Estimated cost in wei
     */
    function estimateCost(FlowParams calldata params)
        external
        view
        override
        returns (uint256 cost)
    {
        return gasEstimator.estimateCost(params);
    }

    // ============ State Queries ============

    function getSupportedTriggers() external view override returns (uint8[] memory) {
        return validator.getSupportedTriggers();
    }

    function getSupportedActions() external view override returns (uint8[] memory) {
        return validator.getSupportedActions();
    }

    function isTriggerSupported(uint8 triggerType) external view override returns (bool) {
        return validator.supportedTriggers(triggerType);
    }

    function isActionSupported(uint8 actionType) external view override returns (bool) {
        return validator.supportedActions(actionType);
    }

    // ============ Internal Simulation Functions ============

    function _simulateTrigger(FlowParams calldata params)
        internal
        view
        returns (bool isValid, string memory message)
    {
        address triggerContract = triggerContracts[params.triggerType];

        // If no contract registered, assume trigger would work
        if (triggerContract == address(0)) {
            return (true, "No trigger contract - assumed valid");
        }

        // Try to check trigger
        try ITrigger(triggerContract).isMet(0, params.triggerData) returns (bool met) {
            if (met) {
                return (true, "Trigger condition met");
            } else {
                return (true, "Trigger not yet met but configuration valid");
            }
        } catch Error(string memory reason) {
            return (false, reason);
        } catch {
            return (false, "Trigger check failed");
        }
    }

    function _simulateAction(FlowParams calldata params)
        internal
        view
        returns (bool isValid, string memory message, bytes memory returnData)
    {
        address actionContract = actionContracts[params.actionType];

        // If no contract registered, assume action would work
        if (actionContract == address(0)) {
            return (true, "No action contract - assumed valid", "");
        }

        // Validate action data structure
        (bool valid, string memory validationMsg) = validator.validateAction(
            params.actionType,
            params.actionData
        );

        if (!valid) {
            return (false, validationMsg, "");
        }

        // Check balance requirements for swap/transfer
        if (params.actionType == 1 || params.actionType == 2) {
            (bool balanceOk, string memory balanceMsg) = _checkBalanceRequirements(params);
            if (!balanceOk) {
                return (false, balanceMsg, "");
            }
        }

        return (true, "Action simulation successful", "");
    }

    function _checkBalanceRequirements(FlowParams calldata params)
        internal
        view
        returns (bool sufficient, string memory message)
    {
        if (params.actionData.length < 96) {
            return (true, "Cannot check balance - insufficient data");
        }

        (address token,, uint256 amount) = abi.decode(
            params.actionData,
            (address, address, uint256)
        );

        // Check mock balance first
        uint256 balance = mockBalances[token][params.user];

        if (balance == 0) {
            // No mock balance set, assume sufficient
            return (true, "No mock balance set - assumed sufficient");
        }

        if (balance >= amount) {
            return (true, "Sufficient balance");
        }

        return (false, "Insufficient balance for action");
    }

    function _applyMockBalances(bytes calldata data) internal {
        // Format: [(token, account, amount), ...]
        // Each entry is 96 bytes (3 * 32)
        uint256 entryCount = data.length / 96;

        for (uint256 i = 0; i < entryCount; i++) {
            uint256 offset = i * 96;
            address token = address(uint160(uint256(bytes32(data[offset:offset + 32]))));
            address account = address(uint160(uint256(bytes32(data[offset + 32:offset + 64]))));
            uint256 amount = uint256(bytes32(data[offset + 64:offset + 96]));

            mockBalances[token][account] = amount;
        }
    }

    function _applyMockPrices(bytes calldata data) internal {
        // Format: [(token, price), ...]
        // Each entry is 64 bytes (2 * 32)
        uint256 entryCount = data.length / 64;

        for (uint256 i = 0; i < entryCount; i++) {
            uint256 offset = i * 64;
            address token = address(uint160(uint256(bytes32(data[offset:offset + 32]))));
            uint256 price = uint256(bytes32(data[offset + 32:offset + 64]));

            mockPrices[token] = price;
        }
    }

    // ============ Stats Functions ============

    function getSimulationStats() external view returns (
        uint256 total,
        uint256 successful,
        uint256 successRate
    ) {
        total = totalSimulations;
        successful = successfulSimulations;
        successRate = totalSimulations > 0
            ? (successfulSimulations * 100) / totalSimulations
            : 0;
    }
}
