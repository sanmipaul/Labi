// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./IFlowSimulator.sol";

/**
 * @title SimulationHelper
 * @notice Helper library for constructing flow parameters and decoding results
 * @dev Provides utilities for common simulation patterns
 */
library SimulationHelper {
    // ============ Trigger Types ============

    uint8 public constant TRIGGER_TIME = 1;
    uint8 public constant TRIGGER_PRICE = 2;
    uint8 public constant TRIGGER_BALANCE = 3;

    // ============ Action Types ============

    uint8 public constant ACTION_SWAP = 1;
    uint8 public constant ACTION_TRANSFER = 2;
    uint8 public constant ACTION_BATCH = 3;
    uint8 public constant ACTION_CROSSCHAIN = 4;

    // ============ Flow Parameter Builders ============

    /**
     * @notice Build parameters for a time-triggered swap flow
     * @param user User address
     * @param executeAt Timestamp to execute
     * @param tokenIn Input token address
     * @param tokenOut Output token address
     * @param amount Amount to swap
     * @param minAmountOut Minimum output amount
     * @return params Complete flow parameters
     */
    function buildTimeTriggeredSwap(
        address user,
        uint256 executeAt,
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 minAmountOut
    ) internal pure returns (IFlowSimulator.FlowParams memory params) {
        params.user = user;
        params.triggerType = TRIGGER_TIME;
        params.actionType = ACTION_SWAP;
        params.triggerValue = executeAt;
        params.triggerData = abi.encode(executeAt);
        params.conditionData = "";
        params.actionData = abi.encode(tokenIn, tokenOut, amount, minAmountOut);
        params.dstEid = 0;
    }

    /**
     * @notice Build parameters for a price-triggered swap flow
     * @param user User address
     * @param token Token to monitor price
     * @param targetPrice Target price to trigger
     * @param isAbove Trigger when price is above (true) or below (false)
     * @param tokenIn Input token for swap
     * @param tokenOut Output token for swap
     * @param amount Amount to swap
     * @return params Complete flow parameters
     */
    function buildPriceTriggeredSwap(
        address user,
        address token,
        uint256 targetPrice,
        bool isAbove,
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) internal pure returns (IFlowSimulator.FlowParams memory params) {
        params.user = user;
        params.triggerType = TRIGGER_PRICE;
        params.actionType = ACTION_SWAP;
        params.triggerValue = targetPrice;
        params.triggerData = abi.encode(token, targetPrice, isAbove);
        params.conditionData = "";
        params.actionData = abi.encode(tokenIn, tokenOut, amount, uint256(0));
        params.dstEid = 0;
    }

    /**
     * @notice Build parameters for a recurring transfer flow
     * @param user User address
     * @param interval Time interval between transfers
     * @param recipient Transfer recipient
     * @param token Token to transfer
     * @param amount Amount per transfer
     * @return params Complete flow parameters
     */
    function buildRecurringTransfer(
        address user,
        uint256 interval,
        address recipient,
        address token,
        uint256 amount
    ) internal pure returns (IFlowSimulator.FlowParams memory params) {
        params.user = user;
        params.triggerType = TRIGGER_TIME;
        params.actionType = ACTION_TRANSFER;
        params.triggerValue = interval;
        params.triggerData = abi.encode(block.timestamp + interval, interval);
        params.conditionData = "";
        params.actionData = abi.encode(token, recipient, amount);
        params.dstEid = 0;
    }

    /**
     * @notice Build parameters for a balance-triggered transfer
     * @param user User address
     * @param monitorToken Token to monitor balance
     * @param threshold Balance threshold to trigger
     * @param isAbove Trigger when above (true) or below (false)
     * @param transferToken Token to transfer
     * @param recipient Transfer recipient
     * @param amount Amount to transfer
     * @return params Complete flow parameters
     */
    function buildBalanceTriggeredTransfer(
        address user,
        address monitorToken,
        uint256 threshold,
        bool isAbove,
        address transferToken,
        address recipient,
        uint256 amount
    ) internal pure returns (IFlowSimulator.FlowParams memory params) {
        params.user = user;
        params.triggerType = TRIGGER_BALANCE;
        params.actionType = ACTION_TRANSFER;
        params.triggerValue = threshold;
        params.triggerData = abi.encode(monitorToken, threshold, isAbove);
        params.conditionData = "";
        params.actionData = abi.encode(transferToken, recipient, amount);
        params.dstEid = 0;
    }

    /**
     * @notice Build parameters for a cross-chain transfer
     * @param user User address
     * @param executeAt Timestamp to execute
     * @param token Token to transfer
     * @param recipient Recipient on destination chain
     * @param amount Amount to transfer
     * @param dstEid Destination chain endpoint ID
     * @return params Complete flow parameters
     */
    function buildCrossChainTransfer(
        address user,
        uint256 executeAt,
        address token,
        address recipient,
        uint256 amount,
        uint32 dstEid
    ) internal pure returns (IFlowSimulator.FlowParams memory params) {
        params.user = user;
        params.triggerType = TRIGGER_TIME;
        params.actionType = ACTION_CROSSCHAIN;
        params.triggerValue = executeAt;
        params.triggerData = abi.encode(executeAt);
        params.conditionData = "";
        params.actionData = abi.encode(token, recipient, amount, dstEid);
        params.dstEid = dstEid;
    }

    // ============ Trigger Data Builders ============

    /**
     * @notice Encode time trigger data
     * @param executeAt Timestamp to execute
     * @return data Encoded trigger data
     */
    function encodeTimeTrigger(uint256 executeAt) internal pure returns (bytes memory) {
        return abi.encode(executeAt);
    }

    /**
     * @notice Encode recurring time trigger data
     * @param startAt Start timestamp
     * @param interval Interval between executions
     * @return data Encoded trigger data
     */
    function encodeRecurringTimeTrigger(
        uint256 startAt,
        uint256 interval
    ) internal pure returns (bytes memory) {
        return abi.encode(startAt, interval);
    }

    /**
     * @notice Encode price trigger data
     * @param token Token to monitor
     * @param targetPrice Target price
     * @param isAbove Whether to trigger above or below
     * @return data Encoded trigger data
     */
    function encodePriceTrigger(
        address token,
        uint256 targetPrice,
        bool isAbove
    ) internal pure returns (bytes memory) {
        return abi.encode(token, targetPrice, isAbove);
    }

    /**
     * @notice Encode balance trigger data
     * @param token Token to monitor
     * @param threshold Balance threshold
     * @param isAbove Whether to trigger above or below
     * @return data Encoded trigger data
     */
    function encodeBalanceTrigger(
        address token,
        uint256 threshold,
        bool isAbove
    ) internal pure returns (bytes memory) {
        return abi.encode(token, threshold, isAbove);
    }

    // ============ Action Data Builders ============

    /**
     * @notice Encode swap action data
     * @param tokenIn Input token
     * @param tokenOut Output token
     * @param amount Amount to swap
     * @param minAmountOut Minimum output
     * @return data Encoded action data
     */
    function encodeSwapAction(
        address tokenIn,
        address tokenOut,
        uint256 amount,
        uint256 minAmountOut
    ) internal pure returns (bytes memory) {
        return abi.encode(tokenIn, tokenOut, amount, minAmountOut);
    }

    /**
     * @notice Encode transfer action data
     * @param token Token to transfer
     * @param recipient Transfer recipient
     * @param amount Amount to transfer
     * @return data Encoded action data
     */
    function encodeTransferAction(
        address token,
        address recipient,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encode(token, recipient, amount);
    }

    /**
     * @notice Encode cross-chain action data
     * @param token Token to transfer
     * @param recipient Recipient on destination
     * @param amount Amount to transfer
     * @param dstEid Destination chain endpoint ID
     * @return data Encoded action data
     */
    function encodeCrossChainAction(
        address token,
        address recipient,
        uint256 amount,
        uint32 dstEid
    ) internal pure returns (bytes memory) {
        return abi.encode(token, recipient, amount, dstEid);
    }

    // ============ Result Decoders ============

    /**
     * @notice Check if simulation was successful
     * @param result Simulation result to check
     * @return success Whether simulation passed
     */
    function isSuccessful(IFlowSimulator.SimulationResult memory result)
        internal
        pure
        returns (bool success)
    {
        return result.wouldSucceed &&
               result.status == IFlowSimulator.SimulationStatus.Success;
    }

    /**
     * @notice Get human-readable status message
     * @param status Simulation status
     * @return message Status message
     */
    function getStatusMessage(IFlowSimulator.SimulationStatus status)
        internal
        pure
        returns (string memory message)
    {
        if (status == IFlowSimulator.SimulationStatus.Success) {
            return "Simulation successful";
        } else if (status == IFlowSimulator.SimulationStatus.TriggerInvalid) {
            return "Invalid trigger configuration";
        } else if (status == IFlowSimulator.SimulationStatus.ActionInvalid) {
            return "Invalid action configuration";
        } else if (status == IFlowSimulator.SimulationStatus.InsufficientBalance) {
            return "Insufficient balance for action";
        } else if (status == IFlowSimulator.SimulationStatus.ConditionNotMet) {
            return "Condition requirements not met";
        } else if (status == IFlowSimulator.SimulationStatus.GasEstimationFailed) {
            return "Unable to estimate gas";
        } else if (status == IFlowSimulator.SimulationStatus.ExecutionReverted) {
            return "Execution would revert";
        } else if (status == IFlowSimulator.SimulationStatus.ValidationFailed) {
            return "Parameter validation failed";
        }
        return "Unknown status";
    }

    /**
     * @notice Extract gas cost info from result
     * @param result Simulation result
     * @return estimatedGas Estimated gas usage
     * @return estimatedCost Estimated cost in wei
     */
    function getGasInfo(IFlowSimulator.SimulationResult memory result)
        internal
        pure
        returns (uint256 estimatedGas, uint256 estimatedCost)
    {
        return (result.estimatedGas, result.estimatedCost);
    }

    // ============ Mock Data Builders ============

    /**
     * @notice Encode mock balance data for simulation
     * @param token Token address
     * @param account Account address
     * @param amount Balance amount
     * @return data Encoded mock balance
     */
    function encodeMockBalance(
        address token,
        address account,
        uint256 amount
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            bytes32(uint256(uint160(token))),
            bytes32(uint256(uint160(account))),
            bytes32(amount)
        );
    }

    /**
     * @notice Encode multiple mock balances
     * @param tokens Token addresses
     * @param accounts Account addresses
     * @param amounts Balance amounts
     * @return data Encoded mock balances
     */
    function encodeMockBalances(
        address[] memory tokens,
        address[] memory accounts,
        uint256[] memory amounts
    ) internal pure returns (bytes memory data) {
        require(
            tokens.length == accounts.length && accounts.length == amounts.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < tokens.length; i++) {
            data = abi.encodePacked(
                data,
                bytes32(uint256(uint160(tokens[i]))),
                bytes32(uint256(uint160(accounts[i]))),
                bytes32(amounts[i])
            );
        }
    }

    /**
     * @notice Encode mock price data for simulation
     * @param token Token address
     * @param price Price value
     * @return data Encoded mock price
     */
    function encodeMockPrice(
        address token,
        uint256 price
    ) internal pure returns (bytes memory) {
        return abi.encodePacked(
            bytes32(uint256(uint160(token))),
            bytes32(price)
        );
    }

    /**
     * @notice Encode multiple mock prices
     * @param tokens Token addresses
     * @param prices Price values
     * @return data Encoded mock prices
     */
    function encodeMockPrices(
        address[] memory tokens,
        uint256[] memory prices
    ) internal pure returns (bytes memory data) {
        require(tokens.length == prices.length, "Array length mismatch");

        for (uint256 i = 0; i < tokens.length; i++) {
            data = abi.encodePacked(
                data,
                bytes32(uint256(uint160(tokens[i]))),
                bytes32(prices[i])
            );
        }
    }
}
