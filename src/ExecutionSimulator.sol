pragma solidity ^0.8.19;

import {IIntentRegistry} from "./IIntentRegistry.sol";
import {IIntentVault} from "./IIntentVault.sol";
import {ITrigger} from "./triggers/ITrigger.sol";
import {IAction} from "./actions/IAction.sol";
import {GasOracle} from "./GasOracle.sol";

contract ExecutionSimulator {
    IIntentRegistry public registry;
    GasOracle public gasOracle;
    mapping(uint256 => ITrigger) public triggerContracts;
    mapping(uint256 => IAction) public actionContracts;

    constructor(address registryAddress, address _gasOracle) {
        require(registryAddress != address(0), "Invalid registry");
        registry = IIntentRegistry(registryAddress);
        gasOracle = GasOracle(_gasOracle);
    }

    function setGasOracle(address _gasOracle) external {
        require(_gasOracle != address(0), "Invalid gas oracle");
        gasOracle = GasOracle(_gasOracle);
    }

    function setTriggerContract(uint8 triggerType, address triggerContract) external {
        require(triggerContract != address(0), "Invalid trigger contract");
        triggerContracts[triggerType] = ITrigger(triggerContract);
    }

    function setActionContract(uint8 actionType, address actionContract) external {
        require(actionContract != address(0), "Invalid action contract");
        actionContracts[actionType] = IAction(actionContract);
    }

    function simulateExecution(uint256 flowId) external view returns (
        bool canExecute,
        string memory reason,
        uint256 estimatedGas,
        uint256 estimatedCost
    ) {
        uint256 startGas = gasleft();
        try this._performSimulation(flowId) returns (bool success, string memory msg_) {
            uint256 gasUsed = startGas - gasleft();
            uint256 cost = 0;
            if (address(gasOracle) != address(0)) {
                cost = gasOracle.estimateCost(gasUsed);
            }
            return (success, msg_, gasUsed, cost);
        } catch Error(string memory error) {
            return (false, error, 0, 0);
        } catch {
            return (false, "Simulation failed", 0, 0);
        }
    }

    function _performSimulation(uint256 flowId)
        external
        view
        returns (bool, string memory)
    {
        IIntentRegistry.IntentFlow memory flow = registry.getFlow(flowId);

        if (flow.user == address(0)) {
            return (false, "Flow does not exist");
        }

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
            return (false, "Trigger not met");
        }

        return (true, "Ready for execution");
    }
}
