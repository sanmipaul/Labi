# Security Documentation

## Zero Address Validation

### Overview
Zero address validation is a critical security measure implemented across the Labi protocol to prevent locked funds and broken functionality.

### What is the Zero Address?
The zero address (`0x0000000000000000000000000000000000000000`) is a special address in Ethereum that:
- Cannot hold or transfer funds
- Has no private key
- Cannot execute transactions
- Is often used to represent uninitialized state

### Security Risks
Without zero address validation:
1. **Locked Funds**: Assets sent to zero address are permanently lost
2. **Broken References**: Contract references to zero address will fail
3. **Invalid State**: Zero address in mappings indicates uninitialized/invalid state
4. **Failed Transactions**: Calls to zero address will always fail

### Implementation

#### IntentRegistry.sol
All functions that accept address parameters validate against zero address:

```solidity
function getUserFlows(address user) external view returns (uint256[] memory) {
    require(user != address(0), "IntentRegistry: user address is zero");
    return userFlows[user];
}
```

**Protected Functions:**
- `getUserFlows(address user)` - Prevents querying flows for invalid user addresses

**Note:** `createFlow` does not need explicit validation as `msg.sender` is guaranteed by the EVM to never be the zero address.

#### IntentVault.sol
All protocol and token address parameters are validated:

```solidity
function approveProtocol(address protocol) external onlyOwner {
    require(protocol != address(0), "IntentVault: protocol address is zero");
    approvedProtocols[protocol] = true;
    emit ProtocolApproved(protocol);
}
```

**Protected Functions:**
- `approveProtocol(address protocol)` - Prevents approving invalid protocol addresses
- `revokeProtocol(address protocol)` - Ensures protocol address is valid
- `setSpendingCap(address token, uint256 cap)` - Validates token address
- `getSpendingCap(address token)` - Prevents queries for invalid tokens
- `getRemainingSpendingCap(address token)` - Ensures valid token address
- `isApprovedProtocol(address protocol)` - Validates protocol address
- `resetSpendingTracker(address token)` - Prevents resetting invalid token trackers

### Benefits
1. **Prevents Fund Loss**: No assets can be locked in unreachable addresses
2. **Ensures Data Integrity**: All address references are valid
3. **Clear Error Messages**: Failed transactions provide specific error messages
4. **Improved UX**: Frontend can catch errors before transaction submission

### Best Practices
When integrating with Labi protocol:
1. Always validate addresses on the frontend before submitting transactions
2. Never use hardcoded zero addresses in production
3. Test address validation in your integration tests
4. Handle validation errors gracefully in your UI

### Testing
To verify zero address validation:
```solidity
// This should revert
vm.expectRevert("IntentVault: protocol address is zero");
vault.approveProtocol(address(0));

// This should revert
vm.expectRevert("IntentRegistry: user address is zero");
registry.getUserFlows(address(0));
```

## Reporting Security Issues
If you discover a security vulnerability, please email security@labi.protocol (replace with actual contact).
