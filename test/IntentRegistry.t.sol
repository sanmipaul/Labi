pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/IntentRegistry.sol";

contract IntentRegistryTest is Test {
    IntentRegistry registry;
    address user1;
    address user2;

    function setUp() public {
        registry = new IntentRegistry();
        user1 = address(0x1111);
        user2 = address(0x2222);
    }

    function test_CreateFlow() public {
        vm.prank(user1);
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](1);
        actions[0] = IIntentRegistry.Action({
            actionType: 1,
            actionData: abi.encode(address(0xAAAA), address(0xBBBB), 10e18, 5e18, block.timestamp + 1 hours)
        });

        uint256 flowId = registry.createFlow(
            1,
            0,
            abi.encode(0, 0, 0),
            abi.encode(100e18, address(0)),
            actions,
            0
        );

        assertEq(flowId, 1);
    }

    function test_GetFlow() public {
        vm.prank(user1);
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](1);
        actions[0] = IIntentRegistry.Action({
            actionType: 1,
            actionData: abi.encode(address(0xAAAA), address(0xBBBB), 10e18, 5e18, block.timestamp + 1 hours)
        });

        uint256 flowId = registry.createFlow(
            1,
            0,
            abi.encode(0, 0, 0),
            abi.encode(100e18, address(0)),
            actions,
            0
        );

        IIntentRegistry.IntentFlow memory flow = registry.getFlow(flowId);
        assertEq(flow.user, user1);
        assertEq(flow.triggerType, 1);
        assertEq(flow.active, true);
        assertEq(flow.actions.length, 1);
        assertEq(flow.actions[0].actionType, 1);
    }

    function test_GetUserFlows() public {
        vm.prank(user1);
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](1);
        actions[0] = IIntentRegistry.Action({
            actionType: 1,
            actionData: abi.encode(address(0xAAAA), address(0xBBBB), 10e18, 5e18, block.timestamp + 1 hours)
        });

        uint256 flowId1 = registry.createFlow(
            1,
            0,
            abi.encode(0, 0, 0),
            abi.encode(100e18, address(0)),
            actions,
            0
        );

        vm.prank(user1);
        uint256 flowId2 = registry.createFlow(
            2,
            50e18,
            abi.encode(address(0x1234), 100e18, true),
            abi.encode(100e18, address(0)),
            actions,
            0
        );

        uint256[] memory userFlows = registry.getUserFlows(user1);
        assertEq(userFlows.length, 2);
        assertEq(userFlows[0], flowId1);
        assertEq(userFlows[1], flowId2);
    }

    function test_UpdateFlowStatus() public {
        vm.prank(user1);
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](1);
        actions[0] = IIntentRegistry.Action({
            actionType: 1,
            actionData: abi.encode(address(0xAAAA), address(0xBBBB), 10e18, 5e18, block.timestamp + 1 hours)
        });

        uint256 flowId = registry.createFlow(
            1,
            0,
            abi.encode(0, 0, 0),
            abi.encode(100e18, address(0)),
            actions,
            0
        );

        IIntentRegistry.IntentFlow memory flowBefore = registry.getFlow(flowId);
        assertEq(flowBefore.active, true);

        vm.prank(user1);
        registry.updateFlowStatus(flowId, false);

        IIntentRegistry.IntentFlow memory flowAfter = registry.getFlow(flowId);
        assertEq(flowAfter.active, false);
    }

    function test_RecordExecution() public {
        vm.prank(user1);
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](1);
        actions[0] = IIntentRegistry.Action({
            actionType: 1,
            actionData: abi.encode(address(0xAAAA), address(0xBBBB), 10e18, 5e18, block.timestamp + 1 hours)
        });

        uint256 flowId = registry.createFlow(
            1,
            0,
            abi.encode(0, 0, 0),
            abi.encode(100e18, address(0)),
            actions,
            0
        );

        IIntentRegistry.IntentFlow memory flowBefore = registry.getFlow(flowId);
        assertEq(flowBefore.executionCount, 0);
        assertEq(flowBefore.lastExecutedAt, 0);

        registry.recordExecution(flowId);

        IIntentRegistry.IntentFlow memory flowAfter = registry.getFlow(flowId);
        assertEq(flowAfter.executionCount, 1);
        assertEq(flowAfter.lastExecutedAt, block.timestamp);
    }

    function test_CannotUpdateFlowStatusIfNotOwner() public {
        vm.prank(user1);
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](1);
        actions[0] = IIntentRegistry.Action({
            actionType: 1,
            actionData: abi.encode(address(0xAAAA), address(0xBBBB), 10e18, 5e18, block.timestamp + 1 hours)
        });

        uint256 flowId = registry.createFlow(
            1,
            0,
            abi.encode(0, 0, 0),
            abi.encode(100e18, address(0)),
            actions,
            0
        );

        vm.prank(user2);
        vm.expectRevert("Only flow owner can update");
        registry.updateFlowStatus(flowId, false);
    }

    function test_InvalidTriggerTypeRevert() public {
        vm.prank(user1);
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](1);
        actions[0] = IIntentRegistry.Action({
            actionType: 1,
            actionData: abi.encode(address(0xAAAA), address(0xBBBB), 10e18, 5e18, block.timestamp + 1 hours)
        });

        vm.expectRevert("Invalid trigger type");
        registry.createFlow(
            5,
            0,
            abi.encode(0, 0, 0),
            abi.encode(100e18, address(0)),
            actions,
            0
        );
    }

    function test_GetNonexistentFlowRevert() public {
        vm.expectRevert("Flow does not exist");
        registry.getFlow(999);
    }

    function test_MultipleUsersMultipleFlows() public {
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](1);
        actions[0] = IIntentRegistry.Action({
            actionType: 1,
            actionData: abi.encode(address(0), address(0), 0, 0, 0)
        });

        vm.prank(user1);
        uint256 user1Flow1 = registry.createFlow(1, 0, abi.encode(0, 0, 0), abi.encode(100e18, address(0)), actions, 0);

        vm.prank(user2);
        uint256 user2Flow1 = registry.createFlow(2, 0, abi.encode(address(0), 0, true), abi.encode(100e18, address(0)), actions, 0);

        uint256[] memory user1Flows = registry.getUserFlows(user1);
        uint256[] memory user2Flows = registry.getUserFlows(user2);

        assertEq(user1Flows.length, 1);
        assertEq(user2Flows.length, 1);
        assertEq(user1Flows[0], user1Flow1);
        assertEq(user2Flows[0], user2Flow1);
    }
}
