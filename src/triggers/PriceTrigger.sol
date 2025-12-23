pragma solidity ^0.8.19;

import {ITrigger} from "./ITrigger.sol";

interface IPriceFeed {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

contract PriceTrigger is ITrigger {
    function triggerType() external pure returns (uint8) {
        return 2;
    }

    function isMet(uint256 flowId, bytes calldata triggerData) external view returns (bool) {
        (address priceFeed, uint256 targetPrice, bool isAbove) = abi.decode(
            triggerData,
            (address, uint256, bool)
        );

        require(priceFeed != address(0), "Invalid price feed");

        int256 currentPrice = _getCurrentPrice(priceFeed);
        require(currentPrice > 0, "Invalid price");

        uint256 price = uint256(currentPrice);

        if (isAbove) {
            return price >= targetPrice;
        } else {
            return price <= targetPrice;
        }
    }

    function _getCurrentPrice(address priceFeed) private view returns (int256) {
        try IPriceFeed(priceFeed).latestRoundData() returns (
            uint80,
            int256 answer,
            uint256,
            uint256,
            uint80
        ) {
            return answer;
        } catch {
            return -1;
        }
    }
}
