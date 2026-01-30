// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/simulation/FlowSimulator.sol";
import "../src/simulation/FlowValidator.sol";
import "../src/simulation/GasEstimator.sol";
import "../src/simulation/IFlowSimulator.sol";

contract MockGasOracle {
    function getGasPrice() external pure returns (uint256) {
        return 30 gwei;
    }

    function estimateCost(uint256 gasAmount) external pure returns (uint256) {
        return gasAmount * 30 gwei;
    }
}

contract FlowSimulatorTest is Test {
    FlowSimulator public simulator;
    FlowValidator public validator;
    GasEstimator public gasEstimator;
    MockGasOracle public mockOracle;

    address public user = address(0x1234);
    address public tokenA = address(0xA);
    address public tokenB = address(0xB);

    function setUp() public {
        mockOracle = new MockGasOracle();
        validator = new FlowValidator();
        gasEstimator = new GasEstimator(address(mockOracle));
        simulator = new FlowSimulator(address(validator), address(gasEstimator));
    }

    // ============ Constructor Tests ============

    function test_Constructor() public view {
        assertEq(simulator.owner(), address(this));
        assertEq(address(simulator.validator()), address(validator));
        assertEq(address(simulator.gasEstimator()), address(gasEstimator));
        assertFalse(simulator.paused());
    }

    // ============ Admin Functions Tests ============

    function test_SetPaused() public {
        assertFalse(simulator.paused());

        simulator.setPaused(true);
        assertTrue(simulator.paused());

        simulator.setPaused(false);
        assertFalse(simulator.paused());
    }

    function test_SetPausedOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert("Only owner");
        simulator.setPaused(true);
    }

    function test_SetValidator() public {
        FlowValidator newValidator = new FlowValidator();

        simulator.setValidator(address(newValidator));

        assertEq(address(simulator.validator()), address(newValidator));
    }

    function test_SetValidatorRevertsZeroAddress() public {
        vm.expectRevert("Invalid validator");
        simulator.setValidator(address(0));
    }

    function test_SetGasEstimator() public {
        GasEstimator newEstimator = new GasEstimator(address(mockOracle));

        simulator.setGasEstimator(address(newEstimator));

        assertEq(address(simulator.gasEstimator()), address(newEstimator));
    }

    function test_SetTriggerContract() public {
        address triggerContract = address(0x999);

        simulator.setTriggerContract(1, triggerContract);

        assertEq(simulator.triggerContracts(1), triggerContract);
    }

    function test_SetActionContract() public {
        address actionContract = address(0x888);

        simulator.setActionContract(1, actionContract);

        assertEq(simulator.actionContracts(1), actionContract);
    }

    // ============ Mock State Tests ============

    function test_SetMockBalance() public {
        simulator.setMockBalance(tokenA, user, 1000e18);

        assertEq(simulator.mockBalances(tokenA, user), 1000e18);
    }

    function test_SetMockPrice() public {
        simulator.setMockPrice(tokenA, 2000e18);

        assertEq(simulator.mockPrices(tokenA), 2000e18);
    }

    function test_ClearMockState() public {
        simulator.setMockBalance(tokenA, user, 1000e18);
        simulator.setMockPrice(tokenA, 2000e18);

        simulator.clearMockState(tokenA, user);

        assertEq(simulator.mockBalances(tokenA, user), 0);
        assertEq(simulator.mockPrices(tokenA), 0);
    }

    // ============ Simulation Tests ============

    function test_SimulateFlowSuccess() public {
        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();

        IFlowSimulator.SimulationResult memory result = simulator.simulateFlow(params);

        assertTrue(result.wouldSucceed);
        assertEq(uint256(result.status), uint256(IFlowSimulator.SimulationStatus.Success));
        assertGt(result.estimatedGas, 0);
        assertGt(result.estimatedCost, 0);
        assertEq(result.timestamp, block.timestamp);
    }

    function test_SimulateFlowValidationFailed() public {
        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();
        params.user = address(0);

        IFlowSimulator.SimulationResult memory result = simulator.simulateFlow(params);

        assertFalse(result.wouldSucceed);
        assertEq(uint256(result.status), uint256(IFlowSimulator.SimulationStatus.ValidationFailed));
    }

    function test_SimulateFlowWhenPaused() public {
        simulator.setPaused(true);

        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();

        vm.expectRevert("Simulator is paused");
        simulator.simulateFlow(params);
    }

    function test_SimulateFlowUpdatesStats() public {
        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();

        simulator.simulateFlow(params);

        (uint256 total, uint256 successful, uint256 rate) = simulator.getSimulationStats();
        assertEq(total, 1);
        assertEq(successful, 1);
        assertEq(rate, 100);
    }

    function test_SimulateFlowMultipleTimes() public {
        IFlowSimulator.FlowParams memory validParams = _buildValidSwapParams();
        IFlowSimulator.FlowParams memory invalidParams = _buildValidSwapParams();
        invalidParams.user = address(0);

        simulator.simulateFlow(validParams);
        simulator.simulateFlow(validParams);
        simulator.simulateFlow(invalidParams);

        (uint256 total, uint256 successful, uint256 rate) = simulator.getSimulationStats();
        assertEq(total, 3);
        assertEq(successful, 2);
        assertEq(rate, 66); // 2/3 = 66%
    }

    // ============ Stateful Simulation Tests ============

    function test_SimulateFlowWithState() public {
        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();

        // Encode mock balances
        bytes memory mockBalancesData = abi.encodePacked(
            bytes32(uint256(uint160(tokenA))),
            bytes32(uint256(uint160(user))),
            bytes32(uint256(1000e18))
        );

        // Encode mock prices
        bytes memory mockPricesData = abi.encodePacked(
            bytes32(uint256(uint160(tokenA))),
            bytes32(uint256(2000e18))
        );

        IFlowSimulator.SimulationResult memory result = simulator.simulateFlowWithState(
            params,
            mockBalancesData,
            mockPricesData
        );

        assertTrue(result.wouldSucceed);
    }

    // ============ Batch Simulation Tests ============

    function test_BatchSimulate() public {
        IFlowSimulator.FlowParams[] memory paramsArray = new IFlowSimulator.FlowParams[](3);
        paramsArray[0] = _buildValidSwapParams();
        paramsArray[1] = _buildValidTransferParams();
        paramsArray[2] = _buildValidSwapParams();

        IFlowSimulator.SimulationResult[] memory results = simulator.batchSimulate(paramsArray);

        assertEq(results.length, 3);
        assertTrue(results[0].wouldSucceed);
        assertTrue(results[1].wouldSucceed);
        assertTrue(results[2].wouldSucceed);
    }

    function test_BatchSimulatePartialFailure() public {
        IFlowSimulator.FlowParams[] memory paramsArray = new IFlowSimulator.FlowParams[](3);
        paramsArray[0] = _buildValidSwapParams();
        paramsArray[1] = _buildValidSwapParams();
        paramsArray[1].user = address(0); // Invalid
        paramsArray[2] = _buildValidSwapParams();

        IFlowSimulator.SimulationResult[] memory results = simulator.batchSimulate(paramsArray);

        assertTrue(results[0].wouldSucceed);
        assertFalse(results[1].wouldSucceed);
        assertTrue(results[2].wouldSucceed);
    }

    // ============ Validation Delegation Tests ============

    function test_ValidateFlow() public view {
        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();

        IFlowSimulator.ValidationResult memory result = simulator.validateFlow(params);

        assertTrue(result.isValid);
    }

    function test_ValidateTrigger() public view {
        bytes memory triggerData = abi.encode(block.timestamp + 1 days);

        (bool isValid, string memory message) = simulator.validateTrigger(1, triggerData);

        assertTrue(isValid);
        assertEq(message, "Valid time trigger");
    }

    function test_ValidateAction() public view {
        bytes memory actionData = abi.encode(tokenA, tokenB, uint256(100e18));

        (bool isValid, string memory message) = simulator.validateAction(1, actionData);

        assertTrue(isValid);
        assertEq(message, "Valid swap action");
    }

    // ============ Gas Estimation Delegation Tests ============

    function test_EstimateGas() public view {
        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();

        IFlowSimulator.GasBreakdown memory breakdown = simulator.estimateGas(params);

        assertGt(breakdown.totalGas, 0);
        assertGt(breakdown.triggerGas, 0);
        assertGt(breakdown.actionGas, 0);
    }

    function test_EstimateCost() public view {
        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();

        uint256 cost = simulator.estimateCost(params);

        assertGt(cost, 0);
    }

    // ============ State Query Tests ============

    function test_GetSupportedTriggers() public view {
        uint8[] memory triggers = simulator.getSupportedTriggers();

        assertGt(triggers.length, 0);
    }

    function test_GetSupportedActions() public view {
        uint8[] memory actions = simulator.getSupportedActions();

        assertGt(actions.length, 0);
    }

    function test_IsTriggerSupported() public view {
        assertTrue(simulator.isTriggerSupported(1));
        assertTrue(simulator.isTriggerSupported(2));
        assertTrue(simulator.isTriggerSupported(3));
        assertFalse(simulator.isTriggerSupported(99));
    }

    function test_IsActionSupported() public view {
        assertTrue(simulator.isActionSupported(1));
        assertTrue(simulator.isActionSupported(2));
        assertTrue(simulator.isActionSupported(3));
        assertTrue(simulator.isActionSupported(4));
        assertFalse(simulator.isActionSupported(99));
    }

    // ============ Balance Check Tests ============

    function test_SimulationWithSufficientMockBalance() public {
        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();

        // Set sufficient mock balance
        simulator.setMockBalance(tokenA, user, 200e18);

        IFlowSimulator.SimulationResult memory result = simulator.simulateFlow(params);

        assertTrue(result.wouldSucceed);
    }

    function test_SimulationWithInsufficientMockBalance() public {
        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();

        // Set insufficient mock balance
        simulator.setMockBalance(tokenA, user, 10e18); // Less than 100e18 required

        IFlowSimulator.SimulationResult memory result = simulator.simulateFlow(params);

        assertFalse(result.wouldSucceed);
        assertEq(uint256(result.status), uint256(IFlowSimulator.SimulationStatus.ActionInvalid));
    }

    // ============ Transfer Simulation Tests ============

    function test_SimulateTransferFlow() public {
        IFlowSimulator.FlowParams memory params = _buildValidTransferParams();

        IFlowSimulator.SimulationResult memory result = simulator.simulateFlow(params);

        assertTrue(result.wouldSucceed);
    }

    // ============ Cross-Chain Simulation Tests ============

    function test_SimulateCrossChainFlow() public {
        IFlowSimulator.FlowParams memory params = _buildCrossChainParams();

        IFlowSimulator.SimulationResult memory result = simulator.simulateFlow(params);

        assertTrue(result.wouldSucceed);
    }

    // ============ Helper Functions ============

    function _buildValidSwapParams()
        internal
        view
        returns (IFlowSimulator.FlowParams memory params)
    {
        params.user = user;
        params.triggerType = 1; // TIME
        params.actionType = 1; // SWAP
        params.triggerValue = block.timestamp + 1 days;
        params.triggerData = abi.encode(block.timestamp + 1 days);
        params.conditionData = "";
        params.actionData = abi.encode(tokenA, tokenB, uint256(100e18));
        params.dstEid = 0;
    }

    function _buildValidTransferParams()
        internal
        view
        returns (IFlowSimulator.FlowParams memory params)
    {
        params.user = user;
        params.triggerType = 1; // TIME
        params.actionType = 2; // TRANSFER
        params.triggerValue = block.timestamp + 1 days;
        params.triggerData = abi.encode(block.timestamp + 1 days);
        params.conditionData = "";
        params.actionData = abi.encode(tokenA, address(0x5678), uint256(50e18));
        params.dstEid = 0;
    }

    function _buildCrossChainParams()
        internal
        view
        returns (IFlowSimulator.FlowParams memory params)
    {
        params.user = user;
        params.triggerType = 1; // TIME
        params.actionType = 4; // CROSSCHAIN
        params.triggerValue = block.timestamp + 1 days;
        params.triggerData = abi.encode(block.timestamp + 1 days);
        params.conditionData = "";
        params.actionData = abi.encode(tokenA, address(0x5678), uint256(100e18), uint32(101));
        params.dstEid = 101;
    }
}
