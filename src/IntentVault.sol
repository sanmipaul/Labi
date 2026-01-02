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
    /// @dev Address of the vault owner
    address private vaultOwner;

    /// @dev Pause status of the vault
    bool private paused;

    /// @dev Mapping of approved protocol addresses
    mapping(address => bool) private approvedProtocols;

    /// @dev Mapping of spending caps per token
    /// @notice Protected against overflow by Solidity 0.8+
    mapping(address => uint256) private spendingCaps;

    /// @dev Mapping of spent amounts per token
    /// @notice Protected against overflow by Solidity 0.8+
    mapping(address => uint256) private spentAmounts;

    /// @notice Emitted when a spending cap is set for a token
    event SpendingCapSet(address indexed token, uint256 cap);

    /// @notice Emitted when spending is reset for a token
    event SpendingReset(address indexed token, uint256 previousSpent);

    /// @notice Emitted when a protocol is approved
    event ProtocolApproved(address indexed protocol);

    /// @notice Emitted when a protocol is revoked
    event ProtocolRevoked(address indexed protocol);

    /// @notice Emitted when the vault is paused
    event Paused();

    /// @notice Emitted when the vault is unpaused
    event Unpaused();

    /// @notice Emitted when spending is recorded
    event SpendingRecorded(address indexed token, uint256 amount, uint256 totalSpent);

    /**
     * @dev Constructor sets the deployer as the vault owner
     * @notice Vault starts in unpaused state
     */
    constructor() {
        vaultOwner = msg.sender;
        paused = false;
    }

    modifier onlyOwner() {
        require(msg.sender == vaultOwner, "IntentVault: caller is not the owner");
        _;
    }

    modifier whenNotPaused() {
        require(!paused, "IntentVault: vault is paused");
        _;
    }

    function owner() external view returns (address) {
        return vaultOwner;
    }

    /**
     * @dev Sets the spending cap for a token and resets spent amounts
     * @param token The token address
     * @param cap The new spending cap
     * @notice Only the owner can call this function
     * @notice Resets the spent amount to 0 when setting a new cap
     */
    function setSpendingCap(address token, uint256 cap) external onlyOwner {
        require(token != address(0), "IntentVault: invalid token address");
        uint256 previousSpent = spentAmounts[token];
        spendingCaps[token] = cap;
        spentAmounts[token] = 0;
        emit SpendingCapSet(token, cap);
        if (previousSpent > 0) {
            emit SpendingReset(token, previousSpent);
        }
    }

    function getSpendingCap(address token) external view returns (uint256) {
        return spendingCaps[token];
    }

    /**
     * @dev Returns the total amount spent for a token
     * @param token The token address
     * @return spent The total amount spent
     */
    function getSpentAmount(address token) external view returns (uint256 spent) {
        return spentAmounts[token];
    }

    /**
     * @dev Returns the remaining spending cap for a token
     * @param token The token address
     * @return remaining The remaining spendable amount
     * @notice Automatically protected against underflow by Solidity 0.8+
     */
    function getRemainingSpendingCap(address token) external view returns (uint256 remaining) {
        uint256 cap = spendingCaps[token];
        uint256 spent = spentAmounts[token];

        // Check if spent exceeds cap (shouldn't happen with proper validation)
        if (spent >= cap) return 0;

        // Solidity 0.8+ provides automatic underflow protection
        // This subtraction will revert if spent > cap (but we already checked above)
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
        uint256 totalSpent = spentAmounts[token];

        // Verify spending cap is not exceeded
        require(totalSpent <= spendingCaps[token], "IntentVault: spending cap exceeded");
        emit SpendingRecorded(token, amount, totalSpent);
    }

    /**
     * @dev Approves a protocol to record spending
     * @param protocol The protocol address to approve
     * @notice Only the owner can call this function
     */
    function approveProtocol(address protocol) external onlyOwner {
        require(protocol != address(0), "IntentVault: invalid protocol address");
        require(!approvedProtocols[protocol], "IntentVault: protocol already approved");
        approvedProtocols[protocol] = true;
        emit ProtocolApproved(protocol);
    }

    /**
     * @dev Revokes approval for a protocol
     * @param protocol The protocol address to revoke
     * @notice Only the owner can call this function
     */
    function revokeProtocol(address protocol) external onlyOwner {
        require(protocol != address(0), "IntentVault: invalid protocol address");
        require(approvedProtocols[protocol], "IntentVault: protocol not approved");
        approvedProtocols[protocol] = false;
        emit ProtocolRevoked(protocol);
    }

    /**
     * @dev Checks if a protocol is approved
     * @param protocol The protocol address to check
     * @return bool True if the protocol is approved
     */
    function isApprovedProtocol(address protocol) external view returns (bool) {
        return approvedProtocols[protocol];
    }

    /**
     * @dev Resets the spending tracker for a token without changing the cap
     * @param token The token address
     * @notice Only the owner can call this function
     */
    function resetSpendingTracker(address token) external onlyOwner {
        require(token != address(0), "IntentVault: invalid token address");
        uint256 previousSpent = spentAmounts[token];
        spentAmounts[token] = 0;
        if (previousSpent > 0) {
            emit SpendingReset(token, previousSpent);
        }
    }

    /**
     * @dev Checks if the vault is paused
     * @return bool True if the vault is paused
     */
    function isPaused() external view returns (bool) {
        return paused;
    }

    /**
     * @dev Pauses the vault, preventing spending operations
     * @notice Only the owner can call this function
     */
    function pause() external onlyOwner {
        require(!paused, "IntentVault: already paused");
        paused = true;
        emit Paused();
    }

    /**
     * @dev Unpauses the vault, allowing spending operations
     * @notice Only the owner can call this function
     */
    function unpause() external onlyOwner {
        require(paused, "IntentVault: not paused");
        paused = false;
        emit Unpaused();
    }
}
