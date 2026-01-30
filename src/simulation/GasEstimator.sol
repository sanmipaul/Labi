// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IFlowSimulator.sol";
import "../GasOracle.sol";

/**
 * @title GasEstimator
 * @notice Estimates gas costs for flow execution
 * @dev Provides detailed gas breakdown for pre-creation analysis
 */
contract GasEstimator {
    // ============ Constants ============

    // Base gas costs
    uint256 public constant BASE_EXECUTION_GAS = 21000;
    uint256 public constant TRIGGER_CHECK_BASE_GAS = 5000;
    uint256 public constant ACTION_EXECUTION_BASE_GAS = 30000;
    uint256 public constant CONDITION_CHECK_BASE_GAS = 3000;
    uint256 public constant STORAGE_WRITE_GAS = 20000;
    uint256 public constant STORAGE_READ_GAS = 2100;
    uint256 public constant CALLDATA_BYTE_GAS = 16;
    uint256 public constant CALLDATA_ZERO_BYTE_GAS = 4;
    uint256 public constant LOG_GAS = 375;
    uint256 public constant LOG_TOPIC_GAS = 375;
    uint256 public constant LOG_DATA_GAS = 8;

    // Trigger-specific gas estimates
    uint256 public constant TIME_TRIGGER_GAS = 8000;
    uint256 public constant PRICE_TRIGGER_GAS = 25000; // Includes oracle call
    uint256 public constant BALANCE_TRIGGER_GAS = 15000;

    // Action-specific gas estimates
    uint256 public constant SWAP_ACTION_GAS = 150000;
    uint256 public constant TRANSFER_ACTION_GAS = 65000;
    uint256 public constant BATCH_ACTION_BASE_GAS = 50000;
    uint256 public constant CROSSCHAIN_ACTION_GAS = 200000;

    // Safety margins
    uint256 public constant GAS_SAFETY_MARGIN = 10; // 10% margin

    // ============ State ============

    GasOracle public gasOracle;
    address public owner;

    // Custom gas overrides
    mapping(uint8 => uint256) public triggerGasOverrides;
    mapping(uint8 => uint256) public actionGasOverrides;

    // Historical gas data for better estimates
    mapping(bytes32 => uint256) public historicalGasUsage;
    mapping(bytes32 => uint256) public executionCounts;

    // ============ Events ============

    event GasOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event GasOverrideSet(bool isTrigger, uint8 typeId, uint256 gasAmount);
    event HistoricalDataRecorded(bytes32 indexed paramsHash, uint256 gasUsed);

    // ============ Modifiers ============

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    // ============ Constructor ============

    constructor(address _gasOracle) {
        owner = msg.sender;
        if (_gasOracle != address(0)) {
            gasOracle = GasOracle(_gasOracle);
        }
    }

    // ============ Admin Functions ============

    function setGasOracle(address _gasOracle) external onlyOwner {
        address oldOracle = address(gasOracle);
        gasOracle = GasOracle(_gasOracle);
        emit GasOracleUpdated(oldOracle, _gasOracle);
    }

    function setTriggerGasOverride(uint8 triggerType, uint256 gasAmount) external onlyOwner {
        triggerGasOverrides[triggerType] = gasAmount;
        emit GasOverrideSet(true, triggerType, gasAmount);
    }

    function setActionGasOverride(uint8 actionType, uint256 gasAmount) external onlyOwner {
        actionGasOverrides[actionType] = gasAmount;
        emit GasOverrideSet(false, actionType, gasAmount);
    }

    // ============ Gas Estimation Functions ============

    /**
     * @notice Estimate total gas for flow execution
     * @param params Flow parameters
     * @return breakdown Detailed gas breakdown
     */
    function estimateGas(IFlowSimulator.FlowParams calldata params)
        external
        view
        returns (IFlowSimulator.GasBreakdown memory breakdown)
    {
        breakdown.triggerGas = _estimateTriggerGas(params.triggerType, params.triggerData);
        breakdown.conditionGas = _estimateConditionGas(params.conditionData);
        breakdown.actionGas = _estimateActionGas(params.actionType, params.actionData);
        breakdown.overheadGas = _estimateOverheadGas(params);

        breakdown.totalGas = breakdown.triggerGas +
            breakdown.conditionGas +
            breakdown.actionGas +
            breakdown.overheadGas;

        // Add safety margin
        breakdown.totalGas = breakdown.totalGas + (breakdown.totalGas * GAS_SAFETY_MARGIN / 100);
    }

    /**
     * @notice Estimate execution cost in native token
     * @param params Flow parameters
     * @return cost Estimated cost in wei
     */
    function estimateCost(IFlowSimulator.FlowParams calldata params)
        external
        view
        returns (uint256 cost)
    {
        IFlowSimulator.GasBreakdown memory breakdown = this.estimateGas(params);

        if (address(gasOracle) != address(0)) {
            cost = gasOracle.estimateCost(breakdown.totalGas);
        } else {
            // Fallback: use current gas price
            cost = breakdown.totalGas * tx.gasprice;
        }
    }

    /**
     * @notice Estimate cost with custom gas price
     * @param params Flow parameters
     * @param gasPrice Custom gas price in wei
     * @return cost Estimated cost in wei
     */
    function estimateCostWithGasPrice(
        IFlowSimulator.FlowParams calldata params,
        uint256 gasPrice
    ) external view returns (uint256 cost) {
        IFlowSimulator.GasBreakdown memory breakdown = this.estimateGas(params);
        cost = breakdown.totalGas * gasPrice;
    }

    /**
     * @notice Get gas estimate using historical data if available
     * @param params Flow parameters
     * @return estimatedGas Best estimate based on historical data
     */
    function estimateGasWithHistory(IFlowSimulator.FlowParams calldata params)
        external
        view
        returns (uint256 estimatedGas)
    {
        bytes32 paramsHash = _hashParams(params);

        if (executionCounts[paramsHash] > 0) {
            // Use historical average
            estimatedGas = historicalGasUsage[paramsHash] / executionCounts[paramsHash];
            // Add small margin for variations
            estimatedGas = estimatedGas + (estimatedGas * 5 / 100);
        } else {
            // Use standard estimation
            IFlowSimulator.GasBreakdown memory breakdown = this.estimateGas(params);
            estimatedGas = breakdown.totalGas;
        }
    }

    // ============ Recording Functions ============

    /**
     * @notice Record actual gas usage for future estimates
     * @param params Flow parameters
     * @param actualGasUsed Actual gas consumed
     */
    function recordGasUsage(
        IFlowSimulator.FlowParams calldata params,
        uint256 actualGasUsed
    ) external {
        bytes32 paramsHash = _hashParams(params);

        historicalGasUsage[paramsHash] += actualGasUsed;
        executionCounts[paramsHash]++;

        emit HistoricalDataRecorded(paramsHash, actualGasUsed);
    }

    // ============ Internal Estimation Functions ============

    function _estimateTriggerGas(uint8 triggerType, bytes calldata triggerData)
        internal
        view
        returns (uint256 gas)
    {
        // Check for custom override
        if (triggerGasOverrides[triggerType] > 0) {
            return triggerGasOverrides[triggerType];
        }

        // Base trigger check gas
        gas = TRIGGER_CHECK_BASE_GAS;

        // Type-specific gas
        if (triggerType == 1) {
            // Time trigger
            gas += TIME_TRIGGER_GAS;
        } else if (triggerType == 2) {
            // Price trigger
            gas += PRICE_TRIGGER_GAS;
        } else if (triggerType == 3) {
            // Balance trigger
            gas += BALANCE_TRIGGER_GAS;
        } else {
            // Default for unknown triggers
            gas += PRICE_TRIGGER_GAS; // Conservative estimate
        }

        // Add calldata cost
        gas += _calculateCalldataGas(triggerData);
    }

    function _estimateConditionGas(bytes calldata conditionData)
        internal
        pure
        returns (uint256 gas)
    {
        if (conditionData.length == 0) {
            return 0;
        }

        gas = CONDITION_CHECK_BASE_GAS;

        // Complex conditions cost more
        if (conditionData.length > 100) {
            gas += (conditionData.length - 100) * 10;
        }

        gas += _calculateCalldataGas(conditionData);
    }

    function _estimateActionGas(uint8 actionType, bytes calldata actionData)
        internal
        view
        returns (uint256 gas)
    {
        // Check for custom override
        if (actionGasOverrides[actionType] > 0) {
            return actionGasOverrides[actionType];
        }

        // Base action execution gas
        gas = ACTION_EXECUTION_BASE_GAS;

        // Type-specific gas
        if (actionType == 1) {
            // Swap action
            gas += SWAP_ACTION_GAS;
        } else if (actionType == 2) {
            // Transfer action
            gas += TRANSFER_ACTION_GAS;
        } else if (actionType == 3) {
            // Batch action
            gas += _estimateBatchActionGas(actionData);
        } else if (actionType == 4) {
            // Cross-chain action
            gas += CROSSCHAIN_ACTION_GAS;
        } else {
            // Default for unknown actions
            gas += SWAP_ACTION_GAS; // Conservative estimate
        }

        gas += _calculateCalldataGas(actionData);
    }

    function _estimateBatchActionGas(bytes calldata actionData)
        internal
        pure
        returns (uint256 gas)
    {
        gas = BATCH_ACTION_BASE_GAS;

        // Estimate number of sub-actions based on data length
        // Assuming ~100 bytes per sub-action on average
        uint256 estimatedSubActions = actionData.length / 100;
        if (estimatedSubActions == 0) estimatedSubActions = 1;

        // Add gas for each sub-action
        gas += estimatedSubActions * 50000;
    }

    function _estimateOverheadGas(IFlowSimulator.FlowParams calldata params)
        internal
        pure
        returns (uint256 gas)
    {
        // Base transaction overhead
        gas = BASE_EXECUTION_GAS;

        // Storage operations (reading flow, updating state)
        gas += STORAGE_READ_GAS * 3; // Read flow, vault, etc.
        gas += STORAGE_WRITE_GAS * 2; // Update execution count, last executed

        // Event emission
        gas += LOG_GAS + LOG_TOPIC_GAS * 3 + LOG_DATA_GAS * 32; // Execution event

        // Cross-chain overhead
        if (params.dstEid != 0) {
            gas += 50000; // Additional overhead for cross-chain
        }
    }

    function _calculateCalldataGas(bytes calldata data)
        internal
        pure
        returns (uint256 gas)
    {
        for (uint256 i = 0; i < data.length; i++) {
            if (data[i] == 0) {
                gas += CALLDATA_ZERO_BYTE_GAS;
            } else {
                gas += CALLDATA_BYTE_GAS;
            }
        }
    }

    // ============ Helper Functions ============

    function _hashParams(IFlowSimulator.FlowParams calldata params)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(
            params.triggerType,
            params.actionType,
            keccak256(params.triggerData),
            keccak256(params.actionData)
        ));
    }

    /**
     * @notice Get current gas price from oracle or transaction
     * @return gasPrice Current gas price in wei
     */
    function getCurrentGasPrice() external view returns (uint256 gasPrice) {
        if (address(gasOracle) != address(0)) {
            gasPrice = gasOracle.getGasPrice();
        } else {
            gasPrice = tx.gasprice;
        }
    }

    /**
     * @notice Estimate cost for multiple flows
     * @param paramsArray Array of flow parameters
     * @return totalCost Combined cost estimate
     * @return individualCosts Array of individual costs
     */
    function estimateBatchCost(IFlowSimulator.FlowParams[] calldata paramsArray)
        external
        view
        returns (uint256 totalCost, uint256[] memory individualCosts)
    {
        individualCosts = new uint256[](paramsArray.length);

        for (uint256 i = 0; i < paramsArray.length; i++) {
            individualCosts[i] = this.estimateCost(paramsArray[i]);
            totalCost += individualCosts[i];
        }
    }
}
