pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/IntentRegistry.sol";
import "../src/IntentVault.sol";
import "../src/FlowExecutor.sol";
import "../src/triggers/TimeTrigger.sol";

contract BatchFlowExecutorTest is Test {
    IntentRegistry registry;
    FlowExecutor executor;
    TimeTrigger timeTrigger;
    address user;

    function setUp() public {
        user = address(this);
        registry = new IntentRegistry();
        executor = new FlowExecutor(address(registry));
        timeTrigger = new TimeTrigger();

        executor.registerTrigger(1, address(timeTrigger));
    }

    function test_ExecuteFlowsBatch_Success() public {
        uint256 currentTime = block.timestamp;
        uint256 dayOfWeek = (currentTime / 1 days) % 7;
        uint256 timeOfDay = currentTime % 1 days;

        bytes memory triggerData = abi.encode(dayOfWeek, timeOfDay, 0);
        bytes memory conditionData = abi.encode(0, address(0));
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](0); // Empty actions for simplicity in trigger test

        uint256 flowId1 = registry.createFlow(1, 0, triggerData, conditionData, actions);
        uint256 flowId2 = registry.createFlow(1, 0, triggerData, conditionData, actions);

        uint256[] memory flowIds = new uint256[](2);
        flowIds[0] = flowId1;
        flowIds[1] = flowId2;

        executor.executeFlowsBatch(flowIds);

        IIntentRegistry.IntentFlow memory flow1 = registry.getFlow(flowId1);
        IIntentRegistry.IntentFlow memory flow2 = registry.getFlow(flowId2);

        assertEq(flow1.executionCount, 1);
        assertEq(flow2.executionCount, 1);
    }

    function test_ExecuteFlowsBatch_PartialSuccess() public {
        uint256 currentTime = block.timestamp;
        uint256 dayOfWeek = (currentTime / 1 days) % 7;
        uint256 timeOfDay = currentTime % 1 days;

        bytes memory triggerData = abi.encode(dayOfWeek, timeOfDay, 0);
        bytes memory conditionData = abi.encode(0, address(0));
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](0);

        uint256 flowId1 = registry.createFlow(1, 0, triggerData, conditionData, actions);
        uint256 flowId2 = registry.createFlow(1, 0, triggerData, conditionData, actions);
        
        // Make flow2 inactive so it fails
        registry.updateFlowStatus(flowId2, false);

        uint256[] memory flowIds = new uint256[](2);
        flowIds[0] = flowId1;
        flowIds[1] = flowId2;

        executor.executeFlowsBatch(flowIds);

        IIntentRegistry.IntentFlow memory flow1 = registry.getFlow(flowId1);
        IIntentRegistry.IntentFlow memory flow2 = registry.getFlow(flowId2);

        assertEq(flow1.executionCount, 1);
        assertEq(flow2.executionCount, 0); // Should not have executed
    }
}
