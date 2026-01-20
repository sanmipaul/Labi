pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "../src/IntentVault.sol";
import "../src/IntentRegistry.sol";
import "../src/FlowExecutor.sol";
import "../src/ExecutionSimulator.sol";
import "../src/GasOracle.sol";
import "../src/triggers/TimeTrigger.sol";
import "../src/triggers/PriceTrigger.sol";
import "../src/actions/SwapAction.sol";
import "../src/actions/CrossChainAction.sol";

contract DeployLabi is Script {
    IntentRegistry public registry;
    FlowExecutor public executor;
    ExecutionSimulator public simulator;
    GasOracle public gasOracle;
    TimeTrigger public timeTrigger;
    PriceTrigger public priceTrigger;
    SwapAction public swapAction;
    CrossChainAction public crossChainAction;

    function run() public {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address lzEndpoint = vm.envAddress("LZ_ENDPOINT"); // LayerZero endpoint address
        vm.startBroadcast(deployerPrivateKey);

        registry = new IntentRegistry();
        console.log("IntentRegistry deployed at:", address(registry));

        executor = new FlowExecutor(address(registry), lzEndpoint);
        console.log("FlowExecutor deployed at:", address(executor));

        simulator = new ExecutionSimulator(address(registry), address(gasOracle));
        console.log("ExecutionSimulator deployed at:", address(simulator));

        timeTrigger = new TimeTrigger();
        console.log("TimeTrigger deployed at:", address(timeTrigger));

        priceTrigger = new PriceTrigger();
        console.log("PriceTrigger deployed at:", address(priceTrigger));

        swapAction = new SwapAction();
        console.log("SwapAction deployed at:", address(swapAction));

        crossChainAction = new CrossChainAction(lzEndpoint);
        console.log("CrossChainAction deployed at:", address(crossChainAction));

        executor.registerTrigger(1, address(timeTrigger));
        executor.registerTrigger(2, address(priceTrigger));
        executor.registerAction(1, address(swapAction));
        executor.registerAction(2, address(crossChainAction));

        console.log("Triggers and actions registered");

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("IntentRegistry:", address(registry));
        console.log("GasOracle:", address(gasOracle));
        console.log("FlowExecutor:", address(executor));
        console.log("ExecutionSimulator:", address(simulator));
        console.log("TimeTrigger:", address(timeTrigger));
        console.log("PriceTrigger:", address(priceTrigger));
        console.log("SwapAction:", address(swapAction));
    }
}
