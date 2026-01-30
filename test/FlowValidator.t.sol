// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/simulation/FlowValidator.sol";
import "../src/simulation/IFlowSimulator.sol";

contract FlowValidatorTest is Test {
    FlowValidator public validator;

    address public user = address(0x1234);
    address public tokenA = address(0xA);
    address public tokenB = address(0xB);

    function setUp() public {
        validator = new FlowValidator();
    }

    // ============ Constructor Tests ============

    function test_Constructor() public view {
        assertEq(validator.owner(), address(this));
        assertTrue(validator.supportedTriggers(1)); // TIME
        assertTrue(validator.supportedTriggers(2)); // PRICE
        assertTrue(validator.supportedTriggers(3)); // BALANCE
        assertTrue(validator.supportedActions(1)); // SWAP
        assertTrue(validator.supportedActions(2)); // TRANSFER
        assertTrue(validator.supportedActions(3)); // BATCH
        assertTrue(validator.supportedActions(4)); // CROSSCHAIN
    }

    // ============ Trigger Registration Tests ============

    function test_RegisterTrigger() public {
        address triggerContract = address(0x999);
        validator.registerTrigger(5, triggerContract);

        assertEq(validator.triggerContracts(5), triggerContract);
        assertTrue(validator.supportedTriggers(5));
    }

    function test_RegisterTriggerRevertsZeroAddress() public {
        vm.expectRevert("Invalid address");
        validator.registerTrigger(5, address(0));
    }

    function test_RegisterTriggerOnlyOwner() public {
        vm.prank(user);
        vm.expectRevert("Only owner");
        validator.registerTrigger(5, address(0x999));
    }

    // ============ Action Registration Tests ============

    function test_RegisterAction() public {
        address actionContract = address(0x888);
        validator.registerAction(5, actionContract);

        assertEq(validator.actionContracts(5), actionContract);
        assertTrue(validator.supportedActions(5));
    }

    function test_RegisterActionRevertsZeroAddress() public {
        vm.expectRevert("Invalid address");
        validator.registerAction(5, address(0));
    }

    // ============ Flow Validation Tests ============

    function test_ValidateFlowValidSwap() public view {
        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();

        IFlowSimulator.ValidationResult memory result = validator.validateFlow(params);

        assertTrue(result.isValid);
        assertTrue(result.triggerValid);
        assertTrue(result.actionValid);
        assertTrue(result.conditionValid);
        assertEq(result.errors.length, 0);
    }

    function test_ValidateFlowZeroUser() public view {
        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();
        params.user = address(0);

        IFlowSimulator.ValidationResult memory result = validator.validateFlow(params);

        assertFalse(result.isValid);
        assertGt(result.errors.length, 0);
    }

    function test_ValidateFlowUnsupportedTrigger() public {
        validator.setTriggerEnabled(1, false);

        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();

        IFlowSimulator.ValidationResult memory result = validator.validateFlow(params);

        assertFalse(result.isValid);
        assertFalse(result.triggerValid);
    }

    function test_ValidateFlowUnsupportedAction() public {
        validator.setActionEnabled(1, false);

        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();

        IFlowSimulator.ValidationResult memory result = validator.validateFlow(params);

        assertFalse(result.isValid);
        assertFalse(result.actionValid);
    }

    function test_ValidateFlowEmptyActionData() public view {
        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();
        params.actionData = "";

        IFlowSimulator.ValidationResult memory result = validator.validateFlow(params);

        assertFalse(result.isValid);
        assertFalse(result.actionValid);
    }

    function test_ValidateFlowCrossChainWarning() public view {
        IFlowSimulator.FlowParams memory params = _buildValidSwapParams();
        params.dstEid = 101; // Cross-chain but action is swap

        IFlowSimulator.ValidationResult memory result = validator.validateFlow(params);

        assertTrue(result.isValid);
        assertGt(result.warnings.length, 0);
    }

    // ============ Time Trigger Validation Tests ============

    function test_ValidateTimeTriggerValid() public view {
        bytes memory triggerData = abi.encode(block.timestamp + 1 days);

        (bool isValid, string memory message) = validator.validateTrigger(1, triggerData);

        assertTrue(isValid);
        assertEq(message, "Valid time trigger");
    }

    function test_ValidateTimeTriggerPast() public view {
        bytes memory triggerData = abi.encode(block.timestamp - 1 days);

        (bool isValid, string memory message) = validator.validateTrigger(1, triggerData);

        assertTrue(isValid); // Still valid, just a warning case
        assertEq(message, "Timestamp is in the past - will trigger immediately");
    }

    function test_ValidateTimeTriggerTooFarFuture() public view {
        bytes memory triggerData = abi.encode(block.timestamp + 400 days * 365);

        (bool isValid, string memory message) = validator.validateTrigger(1, triggerData);

        assertFalse(isValid);
        assertEq(message, "Timestamp too far in the future");
    }

    function test_ValidateTimeTriggerDataTooShort() public view {
        bytes memory triggerData = abi.encode(uint128(123));

        (bool isValid,) = validator.validateTrigger(1, triggerData);

        assertTrue(isValid);
    }

    // ============ Price Trigger Validation Tests ============

    function test_ValidatePriceTriggerValid() public view {
        bytes memory triggerData = abi.encode(tokenA, uint256(2000e18));

        (bool isValid, string memory message) = validator.validateTrigger(2, triggerData);

        assertTrue(isValid);
        assertEq(message, "Valid price trigger");
    }

    function test_ValidatePriceTriggerZeroToken() public view {
        bytes memory triggerData = abi.encode(address(0), uint256(2000e18));

        (bool isValid, string memory message) = validator.validateTrigger(2, triggerData);

        assertFalse(isValid);
        assertEq(message, "Invalid token address in price trigger");
    }

    function test_ValidatePriceTriggerZeroPrice() public view {
        bytes memory triggerData = abi.encode(tokenA, uint256(0));

        (bool isValid, string memory message) = validator.validateTrigger(2, triggerData);

        assertFalse(isValid);
        assertEq(message, "Target price cannot be zero");
    }

    // ============ Balance Trigger Validation Tests ============

    function test_ValidateBalanceTriggerValid() public view {
        bytes memory triggerData = abi.encode(tokenA, uint256(100e18));

        (bool isValid, string memory message) = validator.validateTrigger(3, triggerData);

        assertTrue(isValid);
        assertEq(message, "Valid balance trigger");
    }

    function test_ValidateBalanceTriggerZeroToken() public view {
        bytes memory triggerData = abi.encode(address(0), uint256(100e18));

        (bool isValid, string memory message) = validator.validateTrigger(3, triggerData);

        assertFalse(isValid);
        assertEq(message, "Invalid token address in balance trigger");
    }

    // ============ Swap Action Validation Tests ============

    function test_ValidateSwapActionValid() public view {
        bytes memory actionData = abi.encode(tokenA, tokenB, uint256(100e18));

        (bool isValid, string memory message) = validator.validateAction(1, actionData);

        assertTrue(isValid);
        assertEq(message, "Valid swap action");
    }

    function test_ValidateSwapActionSameToken() public view {
        bytes memory actionData = abi.encode(tokenA, tokenA, uint256(100e18));

        (bool isValid, string memory message) = validator.validateAction(1, actionData);

        assertFalse(isValid);
        assertEq(message, "Cannot swap token to itself");
    }

    function test_ValidateSwapActionZeroAmount() public view {
        bytes memory actionData = abi.encode(tokenA, tokenB, uint256(0));

        (bool isValid, string memory message) = validator.validateAction(1, actionData);

        assertFalse(isValid);
        assertEq(message, "Swap amount cannot be zero");
    }

    function test_ValidateSwapActionZeroTokens() public view {
        bytes memory actionData = abi.encode(address(0), tokenB, uint256(100e18));

        (bool isValid, string memory message) = validator.validateAction(1, actionData);

        assertFalse(isValid);
        assertEq(message, "Invalid token addresses in swap");
    }

    // ============ Transfer Action Validation Tests ============

    function test_ValidateTransferActionValid() public view {
        bytes memory actionData = abi.encode(tokenA, user, uint256(50e18));

        (bool isValid, string memory message) = validator.validateAction(2, actionData);

        assertTrue(isValid);
        assertEq(message, "Valid transfer action");
    }

    function test_ValidateTransferActionZeroRecipient() public view {
        bytes memory actionData = abi.encode(tokenA, address(0), uint256(50e18));

        (bool isValid, string memory message) = validator.validateAction(2, actionData);

        assertFalse(isValid);
        assertEq(message, "Cannot transfer to zero address");
    }

    function test_ValidateTransferActionZeroAmount() public view {
        bytes memory actionData = abi.encode(tokenA, user, uint256(0));

        (bool isValid, string memory message) = validator.validateAction(2, actionData);

        assertFalse(isValid);
        assertEq(message, "Transfer amount cannot be zero");
    }

    // ============ Batch Action Validation Tests ============

    function test_ValidateBatchActionValid() public view {
        bytes memory actionData = abi.encode(
            uint256(2),
            abi.encode(tokenA, tokenB, uint256(100e18)),
            abi.encode(tokenB, user, uint256(50e18))
        );

        (bool isValid, string memory message) = validator.validateAction(3, actionData);

        assertTrue(isValid);
        assertEq(message, "Valid batch action");
    }

    function test_ValidateBatchActionDataTooShort() public view {
        bytes memory actionData = abi.encode(uint256(1));

        (bool isValid, string memory message) = validator.validateAction(3, actionData);

        assertFalse(isValid);
        assertEq(message, "Batch action data too short");
    }

    // ============ Cross-Chain Action Validation Tests ============

    function test_ValidateCrossChainActionValid() public view {
        bytes memory actionData = abi.encode(
            tokenA,
            user,
            uint256(100e18),
            uint32(101)
        );

        (bool isValid, string memory message) = validator.validateAction(4, actionData);

        assertTrue(isValid);
        assertEq(message, "Valid cross-chain action");
    }

    function test_ValidateCrossChainActionDataTooShort() public view {
        bytes memory actionData = abi.encode(tokenA);

        (bool isValid, string memory message) = validator.validateAction(4, actionData);

        assertFalse(isValid);
        assertEq(message, "Cross-chain action data too short");
    }

    // ============ Supported Types Query Tests ============

    function test_GetSupportedTriggers() public view {
        uint8[] memory triggers = validator.getSupportedTriggers();

        assertGt(triggers.length, 0);
        assertEq(triggers[0], 1); // TIME
        assertEq(triggers[1], 2); // PRICE
        assertEq(triggers[2], 3); // BALANCE
    }

    function test_GetSupportedActions() public view {
        uint8[] memory actions = validator.getSupportedActions();

        assertGt(actions.length, 0);
        assertEq(actions[0], 1); // SWAP
        assertEq(actions[1], 2); // TRANSFER
        assertEq(actions[2], 3); // BATCH
        assertEq(actions[3], 4); // CROSSCHAIN
    }

    // ============ Toggle Support Tests ============

    function test_SetTriggerEnabled() public {
        assertTrue(validator.supportedTriggers(1));

        validator.setTriggerEnabled(1, false);
        assertFalse(validator.supportedTriggers(1));

        validator.setTriggerEnabled(1, true);
        assertTrue(validator.supportedTriggers(1));
    }

    function test_SetActionEnabled() public {
        assertTrue(validator.supportedActions(1));

        validator.setActionEnabled(1, false);
        assertFalse(validator.supportedActions(1));

        validator.setActionEnabled(1, true);
        assertTrue(validator.supportedActions(1));
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
}
