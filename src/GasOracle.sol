// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

interface IChainlinkGasPrice {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
}

/**
 * @title GasOracle
 * @notice Provides gas price information for cost estimation
 * @dev Integrates with Chainlink gas price feeds or provides fallback estimations
 */
contract GasOracle is Ownable {
    address public gasPriceFeed;
    uint256 public constant FALLBACK_GAS_PRICE = 0.1 gwei;
    
    event GasPriceFeedUpdated(address indexed newFeed);

    constructor(address _gasPriceFeed) Ownable(msg.sender) {
        gasPriceFeed = _gasPriceFeed;
    }

    /**
     * @notice Sets the Chainlink gas price feed address
     * @param _gasPriceFeed The address of the gas price feed
     */
    function setGasPriceFeed(address _gasPriceFeed) external onlyOwner {
        require(_gasPriceFeed != address(0), "Invalid feed address");
        gasPriceFeed = _gasPriceFeed;
        emit GasPriceFeedUpdated(_gasPriceFeed);
    }

    /**
     * @notice Gets the current gas price in wei
     * @return The current gas price
     */
    function getGasPrice() public view returns (uint256) {
        if (gasPriceFeed == address(0)) {
            return FALLBACK_GAS_PRICE;
        }

        try IChainlinkGasPrice(gasPriceFeed).latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80
        ) {
            if (answer <= 0) return FALLBACK_GAS_PRICE;
            return uint256(answer);
        } catch {
            return FALLBACK_GAS_PRICE;
        }
    }

    /**
     * @notice Estimates the cost of a transaction based on gas used
     * @param gasUsed The amount of gas estimated to be used
     * @return The estimated cost in wei
     */
    function estimateCost(uint256 gasUsed) external view returns (uint256) {
        return gasUsed * getGasPrice();
    }
}
