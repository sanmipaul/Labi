pragma solidity ^0.8.19;

import {IIntentVault} from "./IIntentVault.sol";
import {IAccount, UserOperation, IEntryPoint} from "./ERC4337Interfaces.sol";

contract IntentVault is IIntentVault, IAccount {
    address private vaultOwner;
    bool private paused;
    IEntryPoint private entryPoint;
    address private recoveryAddress;

    mapping(address => bool) private approvedProtocols;
    mapping(address => uint256) private spendingCaps;
    mapping(address => uint256) private spentAmounts;

    event SpendingCapSet(address indexed token, uint256 cap);
    event ProtocolApproved(address indexed protocol);
    event ProtocolRevoked(address indexed protocol);
    event Paused();
    event Unpaused();
    event SpendingRecorded(address indexed token, uint256 amount);

    constructor(address entryPointAddress) {
        vaultOwner = msg.sender;
        paused = false;
        entryPoint = IEntryPoint(entryPointAddress);
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

    function recordSpending(address token, uint256 amount) external whenNotPaused {
        require(approvedProtocols[msg.sender], "Protocol not approved");
        spentAmounts[token] += amount;
        require(spentAmounts[token] <= spendingCaps[token], "Spending cap exceeded");
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

    // ERC-4337 functions
    function validateUserOp(UserOperation calldata userOp, bytes32 userOpHash, uint256 missingAccountFunds)
        external returns (uint256 validationData) {
        require(msg.sender == address(entryPoint), "Only EntryPoint");
        // Simple validation: check signature (placeholder)
        // In real implementation, verify signature against vaultOwner
        require(userOp.signature.length > 0, "Invalid signature");
        // For gasless, handle missing funds
        if (missingAccountFunds > 0) {
            (bool success,) = payable(msg.sender).call{value: missingAccountFunds}("");
            require(success, "Failed to pay missing funds");
        }
        return 0; // validationData
    }

    function execute(address dest, uint256 value, bytes calldata func) external {
        require(msg.sender == address(entryPoint), "Only EntryPoint");
        (bool success,) = dest.call{value: value}(func);
        require(success, "Execution failed");
    }

    function executeBatch(address[] calldata dest, uint256[] calldata value, bytes[] calldata func) external {
        require(msg.sender == address(entryPoint), "Only EntryPoint");
        require(dest.length == value.length && value.length == func.length, "Invalid batch");
        for (uint256 i = 0; i < dest.length; i++) {
            (bool success,) = dest[i].call{value: value[i]}(func[i]);
            require(success, "Batch execution failed");
        }
    }

    // Social Recovery
    function setRecoveryAddress(address _recovery) external onlyOwner {
        recoveryAddress = _recovery;
    }

    function recoverOwnership(address newOwner) external {
        require(msg.sender == recoveryAddress, "Only recovery address");
        vaultOwner = newOwner;
    }
}
