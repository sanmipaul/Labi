pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/triggers/TimeTrigger.sol";
import "../src/triggers/PriceTrigger.sol";

contract TimeTriggerTest is Test {
    TimeTrigger timeTrigger;

    function setUp() public {
        timeTrigger = new TimeTrigger();
    }

    function test_TriggerType() public {
        assertEq(timeTrigger.triggerType(), 1);
    }

    function test_TimeBasedTrigger() public {
        uint256 currentTime = block.timestamp;
        uint256 dayOfWeek = (currentTime / 1 days) % 7;
        uint256 timeOfDay = currentTime % 1 days;

        bytes memory triggerData = abi.encode(dayOfWeek, timeOfDay, 0);
        bool isMet = timeTrigger.isMet(1, triggerData);

        assertTrue(isMet);
    }

    function test_TimeBasedTriggerWithoutPreviousExecution() public {
        uint256 currentTime = block.timestamp;
        uint256 dayOfWeek = (currentTime / 1 days) % 7;
        uint256 timeOfDay = currentTime % 1 days;

        bytes memory triggerData = abi.encode(dayOfWeek, timeOfDay, 0);
        bool isMet = timeTrigger.isMet(1, triggerData);

        assertTrue(isMet);
    }

    function test_InvalidDayOfWeek() public {
        bytes memory triggerData = abi.encode(7, 0, 0);
        vm.expectRevert("Invalid day of week");
        timeTrigger.isMet(1, triggerData);
    }

    function test_InvalidTimeOfDay() public {
        bytes memory triggerData = abi.encode(0, 86400, 0);
        vm.expectRevert("Invalid time of day");
        timeTrigger.isMet(1, triggerData);
    }
}

contract PriceTriggerTest is Test {
    PriceTrigger priceTrigger;
    MockPriceFeed mockPriceFeed;

    function setUp() public {
        priceTrigger = new PriceTrigger();
        mockPriceFeed = new MockPriceFeed();
    }

    function test_TriggerType() public {
        assertEq(priceTrigger.triggerType(), 2);
    }

    function test_PriceAboveTarget() public {
        mockPriceFeed.setPrice(100e18);
        
        bytes memory triggerData = abi.encode(address(mockPriceFeed), 50e18, true);
        bool isMet = priceTrigger.isMet(1, triggerData);

        assertTrue(isMet);
    }

    function test_PriceBelowTarget() public {
        mockPriceFeed.setPrice(30e18);
        
        bytes memory triggerData = abi.encode(address(mockPriceFeed), 50e18, false);
        bool isMet = priceTrigger.isMet(1, triggerData);

        assertTrue(isMet);
    }

    function test_PriceNotAboveTarget() public {
        mockPriceFeed.setPrice(40e18);
        
        bytes memory triggerData = abi.encode(address(mockPriceFeed), 50e18, true);
        bool isMet = priceTrigger.isMet(1, triggerData);

        assertFalse(isMet);
    }

    function test_PriceNotBelowTarget() public {
        mockPriceFeed.setPrice(60e18);
        
        bytes memory triggerData = abi.encode(address(mockPriceFeed), 50e18, false);
        bool isMet = priceTrigger.isMet(1, triggerData);

        assertFalse(isMet);
    }

    function test_InvalidPriceFeed() public {
        bytes memory triggerData = abi.encode(address(0), 50e18, true);
        vm.expectRevert("Invalid price feed");
        priceTrigger.isMet(1, triggerData);
    }
}

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
        return (0, price, 0, block.timestamp, 0);
    }

    function decimals() external pure returns (uint8) {
        return 18;
    }
}
