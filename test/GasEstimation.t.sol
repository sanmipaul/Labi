// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/GasOracle.sol";
import "../src/ExecutionSimulator.sol";
import "../src/IntentRegistry.sol";
import "../src/triggers/TimeTrigger.sol";

contract MockGasPriceFeed {
    int256 private _price;
    function setPrice(int256 price) external { _price = price; }
    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        return (0, _price, 0, 0, 0);
    }
}

contract GasEstimationTest is Test {
    GasOracle oracle;
    ExecutionSimulator simulator;
    IntentRegistry registry;
    TimeTrigger timeTrigger;
    MockGasPriceFeed mockFeed;

    function setUp() public {
        mockFeed = new MockGasPriceFeed();
        mockFeed.setPrice(0.2 gwei);
        
        oracle = new GasOracle(address(mockFeed));
        registry = new IntentRegistry();
        simulator = new ExecutionSimulator(address(registry), address(oracle));
        timeTrigger = new TimeTrigger();
        
        simulator.setTriggerContract(1, address(timeTrigger));
    }

    function test_GetGasPrice() public {
        assertEq(oracle.getGasPrice(), 0.2 gwei);
    }

    function test_FallbackGasPrice() public {
        oracle.setGasPriceFeed(address(0));
        assertEq(oracle.getGasPrice(), 0.1 gwei);
    }

    function test_EstimateCost() public {
        uint256 gasUsed = 100000;
        uint256 expectedCost = gasUsed * 0.2 gwei;
        assertEq(oracle.estimateCost(gasUsed), expectedCost);
    }

    function test_SimulateExecutionWithGasEstimation() public {
        uint256 currentTime = block.timestamp;
        uint256 dayOfWeek = (currentTime / 1 days) % 7;
        uint256 timeOfDay = currentTime % 1 days;

        bytes memory triggerData = abi.encode(dayOfWeek, timeOfDay, 0);
        bytes memory conditionData = "";
        IIntentRegistry.Action[] memory actions = new IIntentRegistry.Action[](0);

        uint256 flowId = registry.createFlow(1, 0, triggerData, conditionData, actions);

        (bool canExecute, string memory reason, uint256 estimatedGas, uint256 estimatedCost) = simulator.simulateExecution(flowId);

        assertTrue(canExecute);
        assertEq(reason, "Ready for execution");
        assertTrue(estimatedGas > 0);
        assertEq(estimatedCost, estimatedGas * 0.2 gwei);
    }
}
