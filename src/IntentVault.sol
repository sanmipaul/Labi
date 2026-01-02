pragma solidity ^0.8.19;

import {IIntentVault} from "./IIntentVault.sol";

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
        require(token != address(0), "IntentVault: token address is zero");
        spendingCaps[token] = cap;
        spentAmounts[token] = 0;
        emit SpendingCapSet(token, cap);
    }

    function getSpendingCap(address token) external view returns (uint256) {
        require(token != address(0), "IntentVault: token address is zero");
        return spendingCaps[token];
    }

    function getRemainingSpendingCap(address token) external view returns (uint256) {
        require(token != address(0), "IntentVault: token address is zero");
        uint256 cap = spendingCaps[token];
        uint256 spent = spentAmounts[token];
        if (spent >= cap) return 0;
        return cap - spent;
    }

    function recordSpending(address token, uint256 amount) external whenNotPaused {
        require(approvedProtocols[msg.sender], "Protocol not approved");
        spentAmounts[token] += amount;
        require(spentAmounts[token] <= spendingCaps[token], "Spending cap exceeded");
        emit SpendingRecorded(token, amount);
    }

    function approveProtocol(address protocol) external onlyOwner {
        require(protocol != address(0), "IntentVault: protocol address is zero");
        approvedProtocols[protocol] = true;
        emit ProtocolApproved(protocol);
    }

    function revokeProtocol(address protocol) external onlyOwner {
        require(protocol != address(0), "IntentVault: protocol address is zero");
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
