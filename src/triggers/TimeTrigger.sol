pragma solidity ^0.8.19;

import {ITrigger} from "./ITrigger.sol";

contract TimeTrigger is ITrigger {
    uint256 private constant SECONDS_PER_WEEK = 7 days;
    uint256 private constant SECONDS_PER_DAY = 1 days;

    function triggerType() external pure returns (uint8) {
        return 1;
    }

    function isMet(uint256 flowId, bytes calldata triggerData) external view returns (bool) {
        (uint256 dayOfWeek, uint256 timeOfDay, uint256 lastExecution) = abi.decode(
            triggerData,
            (uint256, uint256, uint256)
        );

        require(dayOfWeek < 7, "Invalid day of week");
        require(timeOfDay < 86400, "Invalid time of day");

        uint256 currentTimestamp = block.timestamp;
        
        if (lastExecution == 0) {
            return _isMatchingDay(currentTimestamp, dayOfWeek) && 
                   _isMatchingTime(currentTimestamp, timeOfDay);
        }

        uint256 timeSinceLastExecution = currentTimestamp - lastExecution;
        
        return timeSinceLastExecution >= 1 days &&
               _isMatchingDay(currentTimestamp, dayOfWeek) &&
               _isMatchingTime(currentTimestamp, timeOfDay);
    }

    function _isMatchingDay(uint256 timestamp, uint256 targetDay) private pure returns (bool) {
        uint256 daysSinceEpoch = timestamp / SECONDS_PER_DAY;
        uint256 currentDay = daysSinceEpoch % 7;
        return currentDay == targetDay;
    }

    function _isMatchingTime(uint256 timestamp, uint256 targetTime) private pure returns (bool) {
        uint256 timeInDay = timestamp % SECONDS_PER_DAY;
        uint256 tolerance = 3600;
        
        if (timeInDay >= targetTime) {
            return timeInDay - targetTime < tolerance;
        } else {
            return targetTime - timeInDay >= tolerance;
        }
    }
}
