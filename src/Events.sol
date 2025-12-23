pragma solidity ^0.8.19;

contract Events {
    event VaultCreated(address indexed owner, address indexed vault);
    event FlowCreated(
        uint256 indexed flowId,
        address indexed user,
        uint8 triggerType,
        uint256 triggerValue,
        uint256 timestamp
    );
    event FlowExecuted(
        uint256 indexed flowId,
        address indexed user,
        uint256 timestamp,
        bool success
    );
    event FlowStatusChanged(uint256 indexed flowId, bool active, uint256 timestamp);
    event SpendingCapSet(
        address indexed vault,
        address indexed token,
        uint256 cap,
        uint256 timestamp
    );
    event SpendingRecorded(
        address indexed vault,
        address indexed token,
        uint256 amount,
        uint256 remaining,
        uint256 timestamp
    );
    event ProtocolApproved(address indexed vault, address indexed protocol, uint256 timestamp);
    event ProtocolRevoked(address indexed vault, address indexed protocol, uint256 timestamp);
    event VaultPaused(address indexed vault, uint256 timestamp);
    event VaultUnpaused(address indexed vault, uint256 timestamp);
    event ExecutionSimulated(
        uint256 indexed flowId,
        bool canExecute,
        string reason,
        uint256 timestamp
    );
    event TriggerRegistered(uint8 indexed triggerType, address indexed trigger, uint256 timestamp);
    event ActionRegistered(uint8 indexed actionType, address indexed action, uint256 timestamp);
    event RateLimitExceeded(
        address indexed vault,
        uint256 indexed flowId,
        uint256 lastExecution,
        uint256 timestamp
    );
    event RateLimitConfigured(
        address indexed vault,
        uint256 limit,
        uint256 minInterval,
        uint256 timestamp
    );
}
