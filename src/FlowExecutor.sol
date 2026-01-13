// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IIntentRegistry} from "./IIntentRegistry.sol";
import {IIntentVault} from "./IIntentVault.sol";
import {ITrigger} from "./triggers/ITrigger.sol";
import {IAction} from "./actions/IAction.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

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
    
    mapping(uint256 => ITrigger) public triggerContracts;
    mapping(uint256 => IAction) public actionContracts;

    event ExecutionAttempted(uint256 indexed flowId, bool success, string reason);
    event TriggerRegistered(uint8 indexed triggerType, address triggerContract);
    event ActionRegistered(uint8 indexed actionType, address actionContract);

    constructor(address registryAddress) Ownable(msg.sender) {
        require(registryAddress != address(0), "Invalid registry");
        registry = IIntentRegistry(registryAddress);
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

    /**
     * @notice Executes an intent flow if all conditions are met
     * @dev Can only be called when contract is not paused. Checks vault pause state,
     * trigger conditions, and custom conditions before executing the associated action.
     * @param flowId The ID of the flow to execute
     * @return bool Returns true if execution succeeds, false otherwise
     */
    function executeFlow(uint256 flowId) external whenNotPaused returns (bool) {
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

        bytes memory actionData = flow.actionData;
        if (actionData.length == 0) {
            emit ExecutionAttempted(flowId, false, "No action data");
            return false;
        }

        uint8 actionType = 1;
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
        } catch Error(string memory reason) {
            emit ExecutionAttempted(flowId, false, reason);
            return false;
        } catch {
            emit ExecutionAttempted(flowId, false, "Unknown error");
            return false;
        }
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
}
