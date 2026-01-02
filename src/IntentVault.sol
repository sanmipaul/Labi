pragma solidity ^0.8.19;

import {IIntentVault} from "./IIntentVault.sol";

/**
 * @title IntentVault
 * @notice User-owned vault for managing intent flow executions
 * @dev Implements spending caps and protocol approval system
 *
 * Overflow Protection:
 * This contract uses Solidity 0.8.19 which includes automatic overflow/underflow
 * protection. All arithmetic operations will revert on overflow/underflow.
 * This eliminates the need for SafeMath library.
 */
contract IntentVault is IIntentVault {
    address private vaultOwner;
    bool private paused;

    mapping(address => bool) private approvedProtocols;
    mapping(address => uint256) private spendingCaps;
    mapping(address => uint256) private spentAmounts;

    event SpendingCapSet(address indexed token, uint256 cap);
    event ProtocolApproved(address indexed protocol);
    event ProtocolRevoked(address indexed protocol);
    event Paused();
    event Unpaused();
    event SpendingRecorded(address indexed token, uint256 amount);

    constructor() {
        vaultOwner = msg.sender;
        paused = false;
    }

    modifier onlyOwner() {
        require(msg.sender == vaultOwner, "Only owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "Vault is paused");
        _;
    }

    function owner() external view returns (address) {
        return vaultOwner;
    }

    function setSpendingCap(address token, uint256 cap) external onlyOwner {
        spendingCaps[token] = cap;
        spentAmounts[token] = 0;
        emit SpendingCapSet(token, cap);
    }

    function getSpendingCap(address token) external view returns (uint256) {
        return spendingCaps[token];
    }

    function getRemainingSpendingCap(address token) external view returns (uint256) {
        uint256 cap = spendingCaps[token];
        uint256 spent = spentAmounts[token];
        if (spent >= cap) return 0;
        return cap - spent;
    }

    /**
     * @dev Records spending for a token
     * @param token The token address
     * @param amount The amount spent
     * @notice Only approved protocols can call this function
     * @notice Automatically protected against overflow by Solidity 0.8+
     */
    function recordSpending(address token, uint256 amount) external whenNotPaused {
        require(approvedProtocols[msg.sender], "IntentVault: protocol not approved");
        require(amount > 0, "IntentVault: amount must be greater than zero");
        require(token != address(0), "IntentVault: invalid token address");

        // Solidity 0.8+ provides automatic overflow protection
        // This addition will revert if spentAmounts[token] + amount > type(uint256).max
        spentAmounts[token] += amount;

        // Verify spending cap is not exceeded
        require(spentAmounts[token] <= spendingCaps[token], "IntentVault: spending cap exceeded");
        emit SpendingRecorded(token, amount);
    }

    function approveProtocol(address protocol) external onlyOwner {
        approvedProtocols[protocol] = true;
        emit ProtocolApproved(protocol);
    }

    function revokeProtocol(address protocol) external onlyOwner {
        approvedProtocols[protocol] = false;
        emit ProtocolRevoked(protocol);
    }

    function isApprovedProtocol(address protocol) external view returns (bool) {
        return approvedProtocols[protocol];
    }

    function resetSpendingTracker(address token) external onlyOwner {
        spentAmounts[token] = 0;
    }

    function isPaused() external view returns (bool) {
        return paused;
    }

    function pause() external onlyOwner {
        paused = true;
        emit Paused();
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused();
    }
}
