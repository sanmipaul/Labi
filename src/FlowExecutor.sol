// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IIntentRegistry} from "./IIntentRegistry.sol";
import {IIntentVault} from "./IIntentVault.sol";
import {ITrigger} from "./triggers/ITrigger.sol";
import {IAction} from "./actions/IAction.sol";
import {ILayerZeroEndpointV2} from "./LayerZeroInterfaces.sol";
import {MessagingParams, MessagingReceipt, Origin} from "./LayerZeroInterfaces.sol";
import {CrossChainUtils} from "./CrossChainUtils.sol";

/**
 * @title FlowExecutor
 * @notice Executes intent-based automation flows with emergency pause capability
 * @dev Implements Ownable and Pausable patterns for access control and emergency stops.
 * The contract can be paused by the owner to prevent all flow executions during critical
 * situations, providing an emergency stop mechanism for the protocol.
 *
 * Security Features:
 * - Pausable: All flow executions can be halted via pause() during emergencies
 * - Ownable: Only the contract owner can pause/unpause and manage registrations
 * - Access Control: Trigger and action registration restricted to owner
 */
contract FlowExecutor is Ownable, Pausable {
    IIntentRegistry public registry;
    ILayerZeroEndpointV2 public lzEndpoint;
    
    address public protocolFeeRecipient;
    uint16 public protocolFeeBps = 1000; // 10% protocol fee
    uint256 public baseFee = 0.001 ether; // Minimum fee for executor

    mapping(uint256 => ITrigger) public triggerContracts;
    mapping(uint256 => IAction) public actionContracts;
    mapping(uint32 => bytes32) public dstExecutors; // dstEid => dst FlowExecutor address

    event ExecutionAttempted(uint256 indexed flowId, bool success, string reason);
    event TriggerRegistered(uint8 indexed triggerType, address triggerContract);
    event ActionRegistered(uint8 indexed actionType, address actionContract);
    event ProtocolFeeRecipientUpdated(address indexed newRecipient);
    event ProtocolFeeBpsUpdated(uint16 newBps);
    event BaseFeeUpdated(uint256 newBaseFee);
    event FeeDistributed(uint256 indexed flowId, address indexed executor, uint256 executorAmount, uint256 protocolAmount);

    constructor(address registryAddress, address lzEndpointAddress) {
        require(registryAddress != address(0), "Invalid registry");
        require(lzEndpointAddress != address(0), "Invalid LZ endpoint");
        registry = IIntentRegistry(registryAddress);
        lzEndpoint = ILayerZeroEndpointV2(lzEndpointAddress);
    }

    function setBaseFee(uint256 _baseFee) external onlyOwner {
        baseFee = _baseFee;
        emit BaseFeeUpdated(_baseFee);
    }

    /**
     * @notice Registers a new trigger contract for a specific trigger type
     * @dev Only callable by contract owner. Used to configure available trigger types
     * for flow execution.
     * @param triggerType The numeric identifier for the trigger type (1-2)
     * @param triggerContract The address of the trigger contract implementation
     */
    function registerTrigger(uint8 triggerType, address triggerContract) external onlyOwner {
        require(triggerContract != address(0), "Invalid trigger contract");
        require(triggerType > 0 && triggerType <= 2, "Invalid trigger type");
        triggerContracts[triggerType] = ITrigger(triggerContract);
        emit TriggerRegistered(triggerType, triggerContract);
    }

    /**
     * @notice Registers a new action contract for a specific action type
     * @dev Only callable by contract owner. Used to configure available action types
     * for flow execution.
     * @param actionType The numeric identifier for the action type
     * @param actionContract The address of the action contract implementation
     */
    function registerAction(uint8 actionType, address actionContract) external onlyOwner {
        require(actionContract != address(0), "Invalid action contract");
        require(actionType > 0, "Invalid action type");
        actionContracts[actionType] = IAction(actionContract);
        emit ActionRegistered(actionType, actionContract);
    }

    function setDstExecutor(uint32 dstEid, bytes32 dstExecutor) external {
        dstExecutors[dstEid] = dstExecutor;
    }

    function getSupportedChains() external pure returns (uint32[] memory) {
        uint32[] memory chains = new uint32[](2);
        chains[0] = 30101; // Ethereum
        chains[1] = 184;   // Base
        return chains;
    }

    function executeFlow(uint256 flowId) external returns (bool) {
        IIntentRegistry.IntentFlow memory flow = registry.getFlow(flowId);

        require(flow.active, "Flow is not active");
        require(flow.user != address(0), "Flow does not exist");

        address vaultAddress = flow.user;
        IIntentVault vault = IIntentVault(vaultAddress);

        if (vault.isPaused()) {
            emit ExecutionAttempted(flowId, false, "Vault is paused");
            return false;
        }

        ITrigger triggerContract = triggerContracts[flow.triggerType];
        require(address(triggerContract) != address(0), "Trigger not registered");

        if (!triggerContract.isMet(flowId, flow.triggerData)) {
            emit ExecutionAttempted(flowId, false, "Trigger conditions not met");
            return false;
        }

        bytes memory conditionData = flow.conditionData;
        if (conditionData.length > 0) {
            if (!_evaluateCondition(vault, conditionData)) {
                emit ExecutionAttempted(flowId, false, "Condition check failed");
                return false;
            }
        }

        for (uint256 i = 0; i < flow.actions.length; i++) {
            IIntentRegistry.Action memory action = flow.actions[i];
            IAction actionContract = actionContracts[action.actionType];
            
            if (address(actionContract) == address(0)) {
                emit ExecutionAttempted(flowId, false, "Action not registered");
                return false;
            }

        uint8 actionType = flow.actionType;
        if (flow.dstEid != 0) {
            require(CrossChainUtils.isSupportedChain(flow.dstEid), "Unsupported chain");
            actionType = 2; // CrossChainAction
            bytes32 dstAddress = dstExecutors[flow.dstEid];
            require(dstAddress != bytes32(0), "Dst executor not set");
            actionData = abi.encode(flow.dstEid, dstAddress, flowId, actionData);
        }

        IAction actionContract = actionContracts[actionType];
        require(address(actionContract) != address(0), "Action not registered");

        try actionContract.execute(vaultAddress, actionData) returns (bool success) {
            if (success) {
                registry.recordExecution(flowId);
                emit ExecutionAttempted(flowId, true, "Success");
                return true;
            } else {
                emit ExecutionAttempted(flowId, false, "Action execution failed");
                return false;
            }
        }

        registry.recordExecution(flowId);
        _distributeFees(flowId, flow.user, flow.executionFee);
        emit ExecutionAttempted(flowId, true, "Success");
        return true;
    }

    function _distributeFees(uint256 flowId, address vaultAddress, uint256 feeAmount) private {
        if (feeAmount == 0) return;

        IIntentVault vault = IIntentVault(vaultAddress);
        
        // Collect fee from vault
        vault.collectFee(feeAmount);

        uint256 protocolAmount = (feeAmount * protocolFeeBps) / 10000;
        uint256 executorAmount = feeAmount - protocolAmount;

        if (protocolAmount > 0) {
            (bool success, ) = protocolFeeRecipient.call{value: protocolAmount}("");
            require(success, "Protocol fee transfer failed");
        }

        if (executorAmount > 0) {
            (bool success, ) = msg.sender.call{value: executorAmount}("");
            require(success, "Executor fee transfer failed");
        }

        emit FeeDistributed(flowId, msg.sender, executorAmount, protocolAmount);
    }

    function sendCrossChainIntent(uint32 dstEid, bytes32 dstAddress, bytes calldata message, MessagingParams calldata params) external payable {
        lzEndpoint.send{value: msg.value}(params, msg.sender);
    }

    function lzReceive(
        Origin calldata _origin,
        bytes32 _guid,
        bytes calldata _message,
        address _executor,
        bytes calldata _extraData
    ) external payable {
        require(msg.sender == address(lzEndpoint), "Only LZ endpoint");
        // Decode and execute the cross-chain intent
        (uint256 flowId, bytes memory actionData) = abi.decode(_message, (uint256, bytes));
        // Assume we have a way to execute on this chain
        // For now, call executeFlow
        this.executeFlow(flowId);
    }

    function _evaluateCondition(IIntentVault vault, bytes memory conditionData)
        private
        view
        returns (bool)
    {
        (uint256 minBalance, address token) = abi.decode(conditionData, (uint256, address));

        if (token == address(0)) {
            return address(vault).balance >= minBalance;
        } else {
            (bool success, bytes memory data) = token.staticcall(
                abi.encodeWithSignature("balanceOf(address)", address(vault))
            );
            require(success, "Balance check failed");
            uint256 balance = abi.decode(data, (uint256));
            return balance >= minBalance;
        }
    }

    function canExecuteFlow(uint256 flowId) external view returns (bool, string memory) {
        IIntentRegistry.IntentFlow memory flow = registry.getFlow(flowId);

        if (!flow.active) {
            return (false, "Flow is not active");
        }

        address vaultAddress = flow.user;
        IIntentVault vault = IIntentVault(vaultAddress);

        if (vault.isPaused()) {
            return (false, "Vault is paused");
        }

        ITrigger triggerContract = triggerContracts[flow.triggerType];
        if (address(triggerContract) == address(0)) {
            return (false, "Trigger not registered");
        }

        if (!triggerContract.isMet(flowId, flow.triggerData)) {
            return (false, "Trigger conditions not met");
        }

        return (true, "Ready for execution");
    }

    /**
     * @dev Checks if a trigger type is registered
     * @param triggerType The type identifier to check
     * @return bool True if the trigger is registered
     */
    function isTriggerRegistered(uint8 triggerType) external view returns (bool) {
        return address(triggerContracts[triggerType]) != address(0);
    }

    /**
     * @dev Checks if an action type is registered
     * @param actionType The type identifier to check
     * @return bool True if the action is registered
     */
    function isActionRegistered(uint8 actionType) external view returns (bool) {
        return address(actionContracts[actionType]) != address(0);
    }

    /**
     * @dev Gets the registered trigger contract address
     * @param triggerType The type identifier to query
     * @return address The address of the registered trigger contract
     */
    function getTriggerContract(uint8 triggerType) external view returns (address) {
        return address(triggerContracts[triggerType]);
    }

    /**
     * @dev Gets the registered action contract address
     * @param actionType The type identifier to query
     * @return address The address of the registered action contract
     */
    function getActionContract(uint8 actionType) external view returns (address) {
        return address(actionContracts[actionType]);
    }
}
