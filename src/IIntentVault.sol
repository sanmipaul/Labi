pragma solidity ^0.8.19;

interface IIntentVault {
    function owner() external view returns (address);
    function isApprovedProtocol(address protocol) external view returns (bool);
    function getSpendingCap(address token) external view returns (uint256);
    function getRemainingSpendingCap(address token) external view returns (uint256);
    function recordSpending(address token, uint256 amount) external;
    function isPaused() external view returns (bool);
    function pause() external;
    function unpause() external;
    // ERC-4337
    function execute(address dest, uint256 value, bytes calldata func) external;
    function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func) external;
    // Social Recovery
    function setRecoveryAddress(address _recovery) external;
    function recoverOwnership(address newOwner) external;
}
