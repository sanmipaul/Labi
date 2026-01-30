// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IFlowSimulator.sol";
import "../triggers/ITrigger.sol";
import "../actions/IAction.sol";

/**
 * @title FlowValidator
 * @notice Validates flow parameters before simulation or creation
 * @dev Performs comprehensive validation checks on flow configuration
 */
contract FlowValidator {
    // ============ Constants ============

    uint8 public constant TRIGGER_TIME = 1;
    uint8 public constant TRIGGER_PRICE = 2;
    uint8 public constant TRIGGER_BALANCE = 3;

    uint8 public constant ACTION_SWAP = 1;
    uint8 public constant ACTION_TRANSFER = 2;
    uint8 public constant ACTION_BATCH = 3;
    uint8 public constant ACTION_CROSSCHAIN = 4;

    uint256 public constant MAX_TRIGGER_VALUE = type(uint128).max;
    uint256 public constant MIN_TRIGGER_VALUE = 1;
    uint256 public constant MAX_ACTION_DATA_LENGTH = 10000;
    uint256 public constant MAX_TRIGGER_DATA_LENGTH = 5000;

    // ============ State ============

    mapping(uint8 => address) public triggerContracts;
    mapping(uint8 => address) public actionContracts;
    mapping(uint8 => bool) public supportedTriggers;
    mapping(uint8 => bool) public supportedActions;

    address public owner;

    // ============ Events ============

    event TriggerRegistered(uint8 indexed triggerType, address indexed contractAddress);
    event ActionRegistered(uint8 indexed actionType, address indexed contractAddress);
    event TriggerEnabled(uint8 indexed triggerType, bool enabled);
    event ActionEnabled(uint8 indexed actionType, bool enabled);

    // ============ Modifiers ============

    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner");
        _;
    }

    // ============ Constructor ============

    constructor() {
        owner = msg.sender;

        // Enable default trigger types
        supportedTriggers[TRIGGER_TIME] = true;
        supportedTriggers[TRIGGER_PRICE] = true;
        supportedTriggers[TRIGGER_BALANCE] = true;

        // Enable default action types
        supportedActions[ACTION_SWAP] = true;
        supportedActions[ACTION_TRANSFER] = true;
        supportedActions[ACTION_BATCH] = true;
        supportedActions[ACTION_CROSSCHAIN] = true;
    }

    // ============ Admin Functions ============

    function registerTrigger(uint8 triggerType, address contractAddress) external onlyOwner {
        require(contractAddress != address(0), "Invalid address");
        triggerContracts[triggerType] = contractAddress;
        supportedTriggers[triggerType] = true;
        emit TriggerRegistered(triggerType, contractAddress);
    }

    function registerAction(uint8 actionType, address contractAddress) external onlyOwner {
        require(contractAddress != address(0), "Invalid address");
        actionContracts[actionType] = contractAddress;
        supportedActions[actionType] = true;
        emit ActionRegistered(actionType, contractAddress);
    }

    function setTriggerEnabled(uint8 triggerType, bool enabled) external onlyOwner {
        supportedTriggers[triggerType] = enabled;
        emit TriggerEnabled(triggerType, enabled);
    }

    function setActionEnabled(uint8 actionType, bool enabled) external onlyOwner {
        supportedActions[actionType] = enabled;
        emit ActionEnabled(actionType, enabled);
    }

    // ============ Core Validation Functions ============

    /**
     * @notice Validate complete flow parameters
     * @param params Flow parameters to validate
     * @return result Detailed validation result
     */
    function validateFlow(IFlowSimulator.FlowParams calldata params)
        external
        view
        returns (IFlowSimulator.ValidationResult memory result)
    {
        string[] memory warnings = new string[](10);
        string[] memory errors = new string[](10);
        uint256 warningCount = 0;
        uint256 errorCount = 0;

        // Validate user address
        if (params.user == address(0)) {
            errors[errorCount++] = "User address is zero";
        }

        // Validate trigger
        (bool triggerValid, string memory triggerMsg) = _validateTriggerInternal(
            params.triggerType,
            params.triggerValue,
            params.triggerData
        );
        if (!triggerValid) {
            errors[errorCount++] = triggerMsg;
        }
        result.triggerValid = triggerValid;

        // Validate action
        (bool actionValid, string memory actionMsg) = _validateActionInternal(
            params.actionType,
            params.actionData
        );
        if (!actionValid) {
            errors[errorCount++] = actionMsg;
        }
        result.actionValid = actionValid;

        // Validate condition data
        (bool conditionValid, string memory conditionMsg) = _validateCondition(params.conditionData);
        if (!conditionValid) {
            errors[errorCount++] = conditionMsg;
        }
        result.conditionValid = conditionValid;

        // Check cross-chain configuration
        if (params.dstEid != 0 && params.actionType != ACTION_CROSSCHAIN) {
            warnings[warningCount++] = "dstEid set but action is not cross-chain";
        }

        // Check for potential issues
        if (params.triggerValue == 0 && params.triggerType == TRIGGER_PRICE) {
            warnings[warningCount++] = "Price trigger with zero value";
        }

        if (params.actionData.length > MAX_ACTION_DATA_LENGTH / 2) {
            warnings[warningCount++] = "Large action data may increase gas costs";
        }

        // Balance check placeholder
        result.balancesSufficient = true; // Would require vault access for real check

        // Trim arrays to actual size
        result.warnings = _trimStringArray(warnings, warningCount);
        result.errors = _trimStringArray(errors, errorCount);

        result.isValid = errorCount == 0;
    }

    /**
     * @notice Validate trigger configuration
     * @param triggerType Type of trigger
     * @param triggerData Encoded trigger data
     * @return isValid Whether trigger is valid
     * @return message Validation message
     */
    function validateTrigger(uint8 triggerType, bytes calldata triggerData)
        external
        view
        returns (bool isValid, string memory message)
    {
        return _validateTriggerInternal(triggerType, 0, triggerData);
    }

    /**
     * @notice Validate action configuration
     * @param actionType Type of action
     * @param actionData Encoded action data
     * @return isValid Whether action is valid
     * @return message Validation message
     */
    function validateAction(uint8 actionType, bytes calldata actionData)
        external
        view
        returns (bool isValid, string memory message)
    {
        return _validateActionInternal(actionType, actionData);
    }

    // ============ Internal Validation Functions ============

    function _validateTriggerInternal(
        uint8 triggerType,
        uint256 triggerValue,
        bytes calldata triggerData
    ) internal view returns (bool isValid, string memory message) {
        // Check if trigger type is supported
        if (!supportedTriggers[triggerType]) {
            return (false, "Trigger type not supported");
        }

        // Check trigger data length
        if (triggerData.length > MAX_TRIGGER_DATA_LENGTH) {
            return (false, "Trigger data too long");
        }

        // Type-specific validation
        if (triggerType == TRIGGER_TIME) {
            return _validateTimeTrigger(triggerValue, triggerData);
        } else if (triggerType == TRIGGER_PRICE) {
            return _validatePriceTrigger(triggerValue, triggerData);
        } else if (triggerType == TRIGGER_BALANCE) {
            return _validateBalanceTrigger(triggerValue, triggerData);
        }

        // Check if contract exists for trigger
        if (triggerContracts[triggerType] == address(0)) {
            return (true, "No contract registered but type is supported");
        }

        return (true, "Valid trigger");
    }

    function _validateActionInternal(
        uint8 actionType,
        bytes calldata actionData
    ) internal view returns (bool isValid, string memory message) {
        // Check if action type is supported
        if (!supportedActions[actionType]) {
            return (false, "Action type not supported");
        }

        // Check action data length
        if (actionData.length == 0) {
            return (false, "Action data is empty");
        }

        if (actionData.length > MAX_ACTION_DATA_LENGTH) {
            return (false, "Action data too long");
        }

        // Type-specific validation
        if (actionType == ACTION_SWAP) {
            return _validateSwapAction(actionData);
        } else if (actionType == ACTION_TRANSFER) {
            return _validateTransferAction(actionData);
        } else if (actionType == ACTION_BATCH) {
            return _validateBatchAction(actionData);
        } else if (actionType == ACTION_CROSSCHAIN) {
            return _validateCrossChainAction(actionData);
        }

        return (true, "Valid action");
    }

    function _validateCondition(bytes calldata conditionData)
        internal
        pure
        returns (bool isValid, string memory message)
    {
        // Empty condition is valid (no condition)
        if (conditionData.length == 0) {
            return (true, "No condition specified");
        }

        // Basic length check
        if (conditionData.length > MAX_TRIGGER_DATA_LENGTH) {
            return (false, "Condition data too long");
        }

        return (true, "Valid condition");
    }

    // ============ Type-Specific Validation ============

    function _validateTimeTrigger(uint256 triggerValue, bytes calldata triggerData)
        internal
        view
        returns (bool isValid, string memory message)
    {
        // Minimum 32 bytes for timestamp
        if (triggerData.length < 32) {
            return (false, "Time trigger data too short");
        }

        // Decode timestamp
        uint256 timestamp = abi.decode(triggerData, (uint256));

        // Check if timestamp is in the past (warning, not error)
        if (timestamp < block.timestamp) {
            return (true, "Timestamp is in the past - will trigger immediately");
        }

        // Check for reasonable future time (< 10 years)
        if (timestamp > block.timestamp + 315360000) {
            return (false, "Timestamp too far in the future");
        }

        return (true, "Valid time trigger");
    }

    function _validatePriceTrigger(uint256 triggerValue, bytes calldata triggerData)
        internal
        pure
        returns (bool isValid, string memory message)
    {
        // Minimum 64 bytes for token address and price
        if (triggerData.length < 64) {
            return (false, "Price trigger data too short");
        }

        // Decode and validate
        (address token, uint256 targetPrice) = abi.decode(triggerData, (address, uint256));

        if (token == address(0)) {
            return (false, "Invalid token address in price trigger");
        }

        if (targetPrice == 0) {
            return (false, "Target price cannot be zero");
        }

        return (true, "Valid price trigger");
    }

    function _validateBalanceTrigger(uint256 triggerValue, bytes calldata triggerData)
        internal
        pure
        returns (bool isValid, string memory message)
    {
        // Minimum 64 bytes for token and threshold
        if (triggerData.length < 64) {
            return (false, "Balance trigger data too short");
        }

        (address token, uint256 threshold) = abi.decode(triggerData, (address, uint256));

        if (token == address(0)) {
            return (false, "Invalid token address in balance trigger");
        }

        return (true, "Valid balance trigger");
    }

    function _validateSwapAction(bytes calldata actionData)
        internal
        pure
        returns (bool isValid, string memory message)
    {
        // Minimum data for swap: tokenIn, tokenOut, amountIn
        if (actionData.length < 96) {
            return (false, "Swap action data too short");
        }

        (address tokenIn, address tokenOut, uint256 amount) = abi.decode(
            actionData,
            (address, address, uint256)
        );

        if (tokenIn == address(0) || tokenOut == address(0)) {
            return (false, "Invalid token addresses in swap");
        }

        if (tokenIn == tokenOut) {
            return (false, "Cannot swap token to itself");
        }

        if (amount == 0) {
            return (false, "Swap amount cannot be zero");
        }

        return (true, "Valid swap action");
    }

    function _validateTransferAction(bytes calldata actionData)
        internal
        pure
        returns (bool isValid, string memory message)
    {
        // Minimum data: token, recipient, amount
        if (actionData.length < 96) {
            return (false, "Transfer action data too short");
        }

        (address token, address recipient, uint256 amount) = abi.decode(
            actionData,
            (address, address, uint256)
        );

        if (recipient == address(0)) {
            return (false, "Cannot transfer to zero address");
        }

        if (amount == 0) {
            return (false, "Transfer amount cannot be zero");
        }

        return (true, "Valid transfer action");
    }

    function _validateBatchAction(bytes calldata actionData)
        internal
        pure
        returns (bool isValid, string memory message)
    {
        // Batch actions require at least one sub-action
        if (actionData.length < 64) {
            return (false, "Batch action data too short");
        }

        return (true, "Valid batch action");
    }

    function _validateCrossChainAction(bytes calldata actionData)
        internal
        pure
        returns (bool isValid, string memory message)
    {
        // Cross-chain requires destination chain and payload
        if (actionData.length < 64) {
            return (false, "Cross-chain action data too short");
        }

        return (true, "Valid cross-chain action");
    }

    // ============ Helper Functions ============

    function _trimStringArray(string[] memory arr, uint256 length)
        internal
        pure
        returns (string[] memory)
    {
        string[] memory result = new string[](length);
        for (uint256 i = 0; i < length; i++) {
            result[i] = arr[i];
        }
        return result;
    }

    /**
     * @notice Get all supported trigger types
     * @return triggerTypes Array of supported trigger type IDs
     */
    function getSupportedTriggers() external view returns (uint8[] memory) {
        uint8[] memory types = new uint8[](10);
        uint256 count = 0;

        for (uint8 i = 1; i <= 10; i++) {
            if (supportedTriggers[i]) {
                types[count++] = i;
            }
        }

        uint8[] memory result = new uint8[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = types[i];
        }
        return result;
    }

    /**
     * @notice Get all supported action types
     * @return actionTypes Array of supported action type IDs
     */
    function getSupportedActions() external view returns (uint8[] memory) {
        uint8[] memory types = new uint8[](10);
        uint256 count = 0;

        for (uint8 i = 1; i <= 10; i++) {
            if (supportedActions[i]) {
                types[count++] = i;
            }
        }

        uint8[] memory result = new uint8[](count);
        for (uint256 i = 0; i < count; i++) {
            result[i] = types[i];
        }
        return result;
    }
}
