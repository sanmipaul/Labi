// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../../src/triggers/PriceTrigger.sol";

/**
 * @title MockPriceFeed
 * @notice Mock price feed for fuzz testing
 */
contract MockPriceFeed {
    int256 private price;

    function setPrice(int256 _price) external {
        price = _price;
    }

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (1, price, block.timestamp, block.timestamp, 1);
    }
}

/**
 * @title PriceTriggerFuzzTest
 * @notice Fuzz tests for PriceTrigger
 */
contract PriceTriggerFuzzTest is Test {
    PriceTrigger public priceTrigger;
    MockPriceFeed public priceFeed;

    function setUp() public {
        priceTrigger = new PriceTrigger();
        priceFeed = new MockPriceFeed();
    }

    /**
     * @notice Fuzz test: Price above target returns true when isAbove=true
     * @param currentPrice Current price from feed
     * @param targetPrice Target price threshold
     */
    function testFuzz_PriceAboveTarget(uint256 currentPrice, uint256 targetPrice) public {
        currentPrice = bound(currentPrice, 1, type(uint128).max);
        targetPrice = bound(targetPrice, 1, currentPrice); // Target <= current

        priceFeed.setPrice(int256(currentPrice));

        bytes memory triggerData = abi.encode(address(priceFeed), targetPrice, true);

        assertTrue(priceTrigger.isMet(1, triggerData));
    }

    /**
     * @notice Fuzz test: Price below target returns false when isAbove=true
     * @param currentPrice Current price from feed
     * @param targetPrice Target price threshold
     */
    function testFuzz_PriceBelowTargetFails(uint256 currentPrice, uint256 targetPrice) public {
        currentPrice = bound(currentPrice, 1, type(uint128).max - 1);
        targetPrice = bound(targetPrice, currentPrice + 1, type(uint128).max); // Target > current

        priceFeed.setPrice(int256(currentPrice));

        bytes memory triggerData = abi.encode(address(priceFeed), targetPrice, true);

        assertFalse(priceTrigger.isMet(1, triggerData));
    }

    /**
     * @notice Fuzz test: Price below target returns true when isAbove=false
     * @param currentPrice Current price from feed
     * @param targetPrice Target price threshold
     */
    function testFuzz_PriceBelowTargetSuccess(uint256 currentPrice, uint256 targetPrice) public {
        currentPrice = bound(currentPrice, 1, type(uint128).max - 1);
        targetPrice = bound(targetPrice, currentPrice, type(uint128).max); // Target >= current

        priceFeed.setPrice(int256(currentPrice));

        bytes memory triggerData = abi.encode(address(priceFeed), targetPrice, false);

        assertTrue(priceTrigger.isMet(1, triggerData));
    }

    /**
     * @notice Fuzz test: Price above target returns false when isAbove=false
     * @param currentPrice Current price from feed
     * @param targetPrice Target price threshold
     */
    function testFuzz_PriceAboveTargetFails(uint256 currentPrice, uint256 targetPrice) public {
        currentPrice = bound(currentPrice, 2, type(uint128).max);
        targetPrice = bound(targetPrice, 1, currentPrice - 1); // Target < current

        priceFeed.setPrice(int256(currentPrice));

        bytes memory triggerData = abi.encode(address(priceFeed), targetPrice, false);

        assertFalse(priceTrigger.isMet(1, triggerData));
    }

    /**
     * @notice Fuzz test: Exact price match - isAbove=true
     * @param price Price value
     */
    function testFuzz_ExactPriceMatchAbove(uint256 price) public {
        price = bound(price, 1, type(uint128).max);

        priceFeed.setPrice(int256(price));

        bytes memory triggerData = abi.encode(address(priceFeed), price, true);

        // Exact match should return true for isAbove (>=)
        assertTrue(priceTrigger.isMet(1, triggerData));
    }

    /**
     * @notice Fuzz test: Exact price match - isAbove=false
     * @param price Price value
     */
    function testFuzz_ExactPriceMatchBelow(uint256 price) public {
        price = bound(price, 1, type(uint128).max);

        priceFeed.setPrice(int256(price));

        bytes memory triggerData = abi.encode(address(priceFeed), price, false);

        // Exact match should return true for isAbove=false (<=)
        assertTrue(priceTrigger.isMet(1, triggerData));
    }

    /**
     * @notice Fuzz test: Invalid price feed reverts
     */
    function testFuzz_InvalidPriceFeedReverts() public {
        bytes memory triggerData = abi.encode(address(0), uint256(100e18), true);

        vm.expectRevert("Invalid price feed");
        priceTrigger.isMet(1, triggerData);
    }

    /**
     * @notice Fuzz test: Trigger type is always 2
     */
    function testFuzz_TriggerTypeConstant() public {
        assertEq(priceTrigger.triggerType(), 2);
    }

    /**
     * @notice Fuzz test: Price volatility simulation
     * @param prices Array of prices to simulate
     * @param targetPrice Target threshold
     */
    function testFuzz_PriceVolatility(int256[5] memory prices, uint256 targetPrice) public {
        targetPrice = bound(targetPrice, 1, type(uint128).max);

        for (uint256 i = 0; i < 5; i++) {
            prices[i] = int256(bound(uint256(prices[i] > 0 ? prices[i] : -prices[i]), 1, type(uint128).max));

            priceFeed.setPrice(prices[i]);

            bytes memory triggerData = abi.encode(address(priceFeed), targetPrice, true);
            bool result = priceTrigger.isMet(1, triggerData);

            // Verify result matches expectation
            if (uint256(prices[i]) >= targetPrice) {
                assertTrue(result);
            } else {
                assertFalse(result);
            }
        }
    }

    /**
     * @notice Fuzz test: Large price values
     * @param price Large price value
     */
    function testFuzz_LargePriceValues(uint256 price) public {
        price = bound(price, type(uint128).max / 2, type(uint128).max);

        priceFeed.setPrice(int256(price));

        bytes memory triggerData = abi.encode(address(priceFeed), price, true);

        // Should handle large values without overflow
        assertTrue(priceTrigger.isMet(1, triggerData));
    }

    /**
     * @notice Fuzz test: Small price values
     * @param price Small price value
     */
    function testFuzz_SmallPriceValues(uint256 price) public {
        price = bound(price, 1, 1000);

        priceFeed.setPrice(int256(price));

        bytes memory triggerData = abi.encode(address(priceFeed), price, true);

        // Should handle small values correctly
        assertTrue(priceTrigger.isMet(1, triggerData));
    }
}
