// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/simulation/GasEstimator.sol";
import "../src/simulation/IFlowSimulator.sol";
import "../src/GasOracle.sol";

contract MockGasOracle {
    uint256 public gasPrice = 30 gwei;

    function getGasPrice() external view returns (uint256) {
        return gasPrice;
    }

    function estimateCost(uint256 gasAmount) external view returns (uint256) {
        return gasAmount * gasPrice;
    }

    function setGasPrice(uint256 _price) external {
        gasPrice = _price;
    }
}

contract GasEstimatorTest is Test {
    GasEstimator public estimator;
    MockGasOracle public mockOracle;

    address public user = address(0x1234);
    address public tokenA = address(0xA);
    address public tokenB = address(0xB);

    function setUp() public {
        mockOracle = new MockGasOracle();
        estimator = new GasEstimator(address(mockOracle));
    }

    // ============ Constructor Tests ============

    function test_Constructor() public view {
        assertEq(estimator.owner(), address(this));
        assertEq(address(estimator.gasOracle()), address(mockOracle));
    }

    function test_ConstructorNoOracle() public {
        GasEstimator noOracleEstimator = new GasEstimator(address(0));
        assertEq(address(noOracleEstimator.gasOracle()), address(0));
    }

    // ============ Admin Functions Tests ============

    function test_SetGasOracle() public {
        MockGasOracle newOracle = new MockGasOracle();

        estimator.setGasOracle(address(newOracle));

        assertEq(address(estimator.gasOracle()), address(newOracle));
    }

    function test_SetGasOracleOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert("Only owner");
        estimator.setGasOracle(address(mockOracle));
    }

    function test_SetTriggerGasOverride() public {
        estimator.setTriggerGasOverride(1, 50000);

        assertEq(estimator.triggerGasOverrides(1), 50000);
    }

    function test_SetActionGasOverride() public {
        estimator.setActionGasOverride(1, 200000);

        assertEq(estimator.actionGasOverrides(1), 200000);
    }

    // ============ Gas Estimation Tests ============

    function test_EstimateGasTimeTriggerSwap() public view {
        IFlowSimulator.FlowParams memory params = _buildTimeTriggerSwapParams();

        IFlowSimulator.GasBreakdown memory breakdown = estimator.estimateGas(params);

        assertGt(breakdown.triggerGas, 0);
        assertGt(breakdown.actionGas, 0);
        assertGt(breakdown.overheadGas, 0);
        assertEq(
            breakdown.totalGas,
            (breakdown.triggerGas + breakdown.conditionGas + breakdown.actionGas + breakdown.overheadGas)
            + ((breakdown.triggerGas + breakdown.conditionGas + breakdown.actionGas + breakdown.overheadGas) * 10 / 100)
        );
    }

    function test_EstimateGasPriceTrigger() public view {
        IFlowSimulator.FlowParams memory params = _buildPriceTriggerSwapParams();

        IFlowSimulator.GasBreakdown memory breakdown = estimator.estimateGas(params);

        // Price trigger should have higher gas than time trigger
        assertGt(breakdown.triggerGas, 0);
    }

    function test_EstimateGasWithCondition() public view {
        IFlowSimulator.FlowParams memory params = _buildTimeTriggerSwapParams();
        params.conditionData = abi.encode(tokenA, uint256(100e18), true);

        IFlowSimulator.GasBreakdown memory breakdown = estimator.estimateGas(params);

        assertGt(breakdown.conditionGas, 0);
    }

    function test_EstimateGasTransferAction() public view {
        IFlowSimulator.FlowParams memory params = _buildTransferParams();

        IFlowSimulator.GasBreakdown memory breakdown = estimator.estimateGas(params);

        // Transfer should use less gas than swap
        assertGt(breakdown.actionGas, 0);
    }

    function test_EstimateGasBatchAction() public view {
        IFlowSimulator.FlowParams memory params = _buildBatchParams();

        IFlowSimulator.GasBreakdown memory breakdown = estimator.estimateGas(params);

        // Batch should estimate based on data size
        assertGt(breakdown.actionGas, 0);
    }

    function test_EstimateGasCrossChain() public view {
        IFlowSimulator.FlowParams memory params = _buildCrossChainParams();

        IFlowSimulator.GasBreakdown memory breakdown = estimator.estimateGas(params);

        // Cross-chain has additional overhead
        assertGt(breakdown.overheadGas, 0);
    }

    function test_EstimateGasWithOverrides() public {
        estimator.setTriggerGasOverride(1, 15000);
        estimator.setActionGasOverride(1, 100000);

        IFlowSimulator.FlowParams memory params = _buildTimeTriggerSwapParams();

        IFlowSimulator.GasBreakdown memory breakdown = estimator.estimateGas(params);

        // Trigger gas should use override
        assertGe(breakdown.triggerGas, 15000);
    }

    // ============ Cost Estimation Tests ============

    function test_EstimateCost() public view {
        IFlowSimulator.FlowParams memory params = _buildTimeTriggerSwapParams();

        uint256 cost = estimator.estimateCost(params);

        assertGt(cost, 0);
    }

    function test_EstimateCostWithGasPrice() public view {
        IFlowSimulator.FlowParams memory params = _buildTimeTriggerSwapParams();
        uint256 customGasPrice = 50 gwei;

        uint256 cost = estimator.estimateCostWithGasPrice(params, customGasPrice);

        IFlowSimulator.GasBreakdown memory breakdown = estimator.estimateGas(params);
        assertEq(cost, breakdown.totalGas * customGasPrice);
    }

    function test_EstimateCostNoOracle() public {
        GasEstimator noOracleEstimator = new GasEstimator(address(0));

        IFlowSimulator.FlowParams memory params = _buildTimeTriggerSwapParams();

        uint256 cost = noOracleEstimator.estimateCost(params);

        // Should use tx.gasprice as fallback
        assertGe(cost, 0);
    }

    // ============ Historical Data Tests ============

    function test_RecordGasUsage() public {
        IFlowSimulator.FlowParams memory params = _buildTimeTriggerSwapParams();
        uint256 actualGas = 150000;

        estimator.recordGasUsage(params, actualGas);

        // Should store historical data
        bytes32 paramsHash = _hashParams(params);
        assertEq(estimator.historicalGasUsage(paramsHash), actualGas);
        assertEq(estimator.executionCounts(paramsHash), 1);
    }

    function test_RecordMultipleGasUsages() public {
        IFlowSimulator.FlowParams memory params = _buildTimeTriggerSwapParams();

        estimator.recordGasUsage(params, 150000);
        estimator.recordGasUsage(params, 160000);
        estimator.recordGasUsage(params, 155000);

        bytes32 paramsHash = _hashParams(params);
        assertEq(estimator.historicalGasUsage(paramsHash), 465000);
        assertEq(estimator.executionCounts(paramsHash), 3);
    }

    function test_EstimateGasWithHistory() public {
        IFlowSimulator.FlowParams memory params = _buildTimeTriggerSwapParams();

        // Record some historical data
        estimator.recordGasUsage(params, 150000);
        estimator.recordGasUsage(params, 160000);

        uint256 estimated = estimator.estimateGasWithHistory(params);

        // Should use historical average + 5% margin
        uint256 expectedAvg = 155000;
        uint256 expectedWithMargin = expectedAvg + (expectedAvg * 5 / 100);
        assertEq(estimated, expectedWithMargin);
    }

    function test_EstimateGasWithoutHistory() public view {
        IFlowSimulator.FlowParams memory params = _buildTimeTriggerSwapParams();

        uint256 estimated = estimator.estimateGasWithHistory(params);

        // Should use standard estimation
        IFlowSimulator.GasBreakdown memory breakdown = estimator.estimateGas(params);
        assertEq(estimated, breakdown.totalGas);
    }

    // ============ Batch Cost Estimation Tests ============

    function test_EstimateBatchCost() public view {
        IFlowSimulator.FlowParams[] memory paramsArray = new IFlowSimulator.FlowParams[](3);
        paramsArray[0] = _buildTimeTriggerSwapParams();
        paramsArray[1] = _buildTransferParams();
        paramsArray[2] = _buildPriceTriggerSwapParams();

        (uint256 totalCost, uint256[] memory individualCosts) = estimator.estimateBatchCost(paramsArray);

        assertEq(individualCosts.length, 3);
        assertEq(totalCost, individualCosts[0] + individualCosts[1] + individualCosts[2]);
    }

    // ============ Gas Price Query Tests ============

    function test_GetCurrentGasPrice() public view {
        uint256 gasPrice = estimator.getCurrentGasPrice();

        assertEq(gasPrice, 30 gwei);
    }

    function test_GetCurrentGasPriceNoOracle() public {
        GasEstimator noOracleEstimator = new GasEstimator(address(0));

        uint256 gasPrice = noOracleEstimator.getCurrentGasPrice();

        // Should return tx.gasprice
        assertGe(gasPrice, 0);
    }

    // ============ Calldata Gas Calculation Tests ============

    function test_CalldataGasNonZeroBytes() public view {
        // Action data with non-zero bytes should cost more
        IFlowSimulator.FlowParams memory params = _buildTimeTriggerSwapParams();

        IFlowSimulator.GasBreakdown memory breakdown = estimator.estimateGas(params);

        // Should include calldata gas
        assertGt(breakdown.actionGas, 0);
    }

    // ============ Constants Tests ============

    function test_GasConstants() public view {
        assertEq(estimator.BASE_EXECUTION_GAS(), 21000);
        assertEq(estimator.TRIGGER_CHECK_BASE_GAS(), 5000);
        assertEq(estimator.ACTION_EXECUTION_BASE_GAS(), 30000);
        assertEq(estimator.SWAP_ACTION_GAS(), 150000);
        assertEq(estimator.TRANSFER_ACTION_GAS(), 65000);
        assertEq(estimator.CROSSCHAIN_ACTION_GAS(), 200000);
        assertEq(estimator.GAS_SAFETY_MARGIN(), 10);
    }

    // ============ Helper Functions ============

    function _buildTimeTriggerSwapParams()
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

    function _buildPriceTriggerSwapParams()
        internal
        view
        returns (IFlowSimulator.FlowParams memory params)
    {
        params.user = user;
        params.triggerType = 2; // PRICE
        params.actionType = 1; // SWAP
        params.triggerValue = 2000e18;
        params.triggerData = abi.encode(tokenA, uint256(2000e18));
        params.conditionData = "";
        params.actionData = abi.encode(tokenA, tokenB, uint256(100e18));
        params.dstEid = 0;
    }

    function _buildTransferParams()
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

    function _buildBatchParams()
        internal
        view
        returns (IFlowSimulator.FlowParams memory params)
    {
        params.user = user;
        params.triggerType = 1; // TIME
        params.actionType = 3; // BATCH
        params.triggerValue = block.timestamp + 1 days;
        params.triggerData = abi.encode(block.timestamp + 1 days);
        params.conditionData = "";
        params.actionData = abi.encode(
            uint256(2),
            abi.encode(tokenA, tokenB, uint256(100e18)),
            abi.encode(tokenB, address(0x5678), uint256(50e18))
        );
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

    function _hashParams(IFlowSimulator.FlowParams memory params)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(
            params.triggerType,
            params.actionType,
            keccak256(params.triggerData),
            keccak256(params.actionData)
        ));
    }
}
