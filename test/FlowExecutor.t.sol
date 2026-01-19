pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/IntentRegistry.sol";
import "../src/IntentVault.sol";
import "../src/FlowExecutor.sol";
import "../src/triggers/TimeTrigger.sol";
import "../src/actions/SwapAction.sol";

contract FlowExecutorTest is Test {
    IntentRegistry registry;
    FlowExecutor executor;
    TimeTrigger timeTrigger;
    IntentVault vault;
    address user;

    function setUp() public {
        user = address(this);
        vault = new IntentVault();
        registry = new IntentRegistry();
        executor = new FlowExecutor(address(registry));
        timeTrigger = new TimeTrigger();

        executor.registerTrigger(1, address(timeTrigger));
    }

    function test_RegisterTrigger() public {
        assertEq(address(executor.triggerContracts(1)), address(timeTrigger));
    }

    function test_CanExecuteFlowReturnsReadyStatus() public {
        uint256 currentTime = block.timestamp;
        uint256 dayOfWeek = (currentTime / 1 days) % 7;
        uint256 timeOfDay = currentTime % 1 days;

        bytes memory triggerData = abi.encode(dayOfWeek, timeOfDay, 0);
        bytes memory conditionData = abi.encode(0, address(0));
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](1);
        actions[0] = IIntentRegistry.Action({
            actionType: 1,
            actionData: abi.encode(address(0xAAAA), address(0xBBBB), 10e18, 5e18, block.timestamp + 1 hours)
        });

        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actions);

        (bool canExecute, string memory reason) = executor.canExecuteFlow(flowId);
        assertTrue(canExecute);
        assertEq(reason, "Ready for execution");
    }

    function test_CannotExecuteInactiveFlow() public {
        uint256 currentTime = block.timestamp;
        uint256 dayOfWeek = (currentTime / 1 days) % 7;
        uint256 timeOfDay = currentTime % 1 days;

        bytes memory triggerData = abi.encode(dayOfWeek, timeOfDay, 0);
        bytes memory conditionData = abi.encode(0, address(0));
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](1);
        actions[0] = IIntentRegistry.Action({
            actionType: 1,
            actionData: abi.encode(address(0xAAAA), address(0xBBBB), 10e18, 5e18, block.timestamp + 1 hours)
        });

        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actions);
        registry.updateFlowStatus(flowId, false);

        (bool canExecute, string memory reason) = executor.canExecuteFlow(flowId);
        assertFalse(canExecute);
        assertEq(reason, "Flow is not active");
    }

    function test_CannotExecuteWhenVaultPaused() public {
        uint256 currentTime = block.timestamp;
        uint256 dayOfWeek = (currentTime / 1 days) % 7;
        uint256 timeOfDay = currentTime % 1 days;

        bytes memory triggerData = abi.encode(dayOfWeek, timeOfDay, 0);
        bytes memory conditionData = abi.encode(0, address(0));
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](1);
        actions[0] = IIntentRegistry.Action({
            actionType: 1,
            actionData: abi.encode(address(0xAAAA), address(0xBBBB), 10e18, 5e18, block.timestamp + 1 hours)
        });

        vm.prank(user);
        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actions);

        vault.pause();

        (bool canExecute, string memory reason) = executor.canExecuteFlow(flowId);
        assertFalse(canExecute);
        assertEq(reason, "Vault is paused");
    }

    function test_TriggerNotRegisteredError() public {
        FlowExecutor testExecutor = new FlowExecutor(address(registry));
        
        uint256 currentTime = block.timestamp;
        uint256 dayOfWeek = (currentTime / 1 days) % 7;
        uint256 timeOfDay = currentTime % 1 days;

        bytes memory triggerData = abi.encode(dayOfWeek, timeOfDay, 0);
        bytes memory conditionData = abi.encode(0, address(0));
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](1);
        actions[0] = IIntentRegistry.Action({
            actionType: 1,
            actionData: abi.encode(address(0xAAAA), address(0xBBBB), 10e18, 5e18, block.timestamp + 1 hours)
        });

        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actions);

        (bool canExecute, string memory reason) = testExecutor.canExecuteFlow(flowId);
        assertFalse(canExecute);
        assertEq(reason, "Trigger not registered");
    }

    function test_ExecutionAttemptsInvalidTriggerType() public {
        bytes memory triggerData = abi.encode(0, 0, 0);
        bytes memory conditionData = abi.encode(0, address(0));
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](1);
        actions[0] = IIntentRegistry.Action({
            actionType: 1,
            actionData: abi.encode(address(0xAAAA), address(0xBBBB), 10e18, 5e18, block.timestamp + 1 hours)
        });

        vm.prank(user);
        uint256 flowId = registry.createFlow(99, 0, triggerData, conditionData, actions);

        bool success = executor.executeFlow(flowId);
        assertFalse(success);
    }
}
