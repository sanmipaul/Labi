pragma solidity ^0.8.19;

contract RateLimiter {
    mapping(address => mapping(uint256 => uint256)) public lastExecutionTime;
    mapping(address => uint256) public executionLimitPerDay;

    event RateLimitExceeded(address indexed vault, uint256 lastExecution, uint256 now);
    event ExecutionLimitSet(address indexed vault, uint256 limit);

    function setExecutionLimitPerDay(address vault, uint256 limit) external {
        require(vault != address(0), "Invalid vault address");
        require(limit > 0, "Limit must be greater than zero");
        executionLimitPerDay[vault] = limit;
        emit ExecutionLimitSet(vault, limit);
    }

    function canExecute(address vault, uint256 flowId) external view returns (bool) {
        uint256 lastExecution = lastExecutionTime[vault][flowId];
        
        if (lastExecution == 0) {
            return true;
        }

        uint256 timeSinceLastExecution = block.timestamp - lastExecution;
        
        uint256 minInterval = 1 days / executionLimitPerDay[vault];
        
        return timeSinceLastExecution >= minInterval;
    }

    function recordExecution(address vault, uint256 flowId) external {
        require(vault != address(0), "Invalid vault address");
        lastExecutionTime[vault][flowId] = block.timestamp;
    }

    function getLastExecutionTime(address vault, uint256 flowId) external view returns (uint256) {
        return lastExecutionTime[vault][flowId];
    }

    function getMinimumInterval(address vault) external view returns (uint256) {
        uint256 limit = executionLimitPerDay[vault];
        if (limit == 0) return 0;
        return 1 days / limit;
    }
}
