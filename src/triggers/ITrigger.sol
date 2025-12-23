pragma solidity ^0.8.19;

interface ITrigger {
    function isMet(uint256 flowId, bytes calldata triggerData) external view returns (bool);
    function triggerType() external pure returns (uint8);
}
