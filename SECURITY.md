# Security Policy

## Security Updates

### [2026-01-02] Reentrancy Protection for SwapAction Contract

**Issue:** Reentrancy vulnerability in SwapAction contract (Issue #5)

**Severity:** Medium

**Description:**
The SwapAction contract performed multiple external calls to ERC20 tokens, Uniswap router, and the IntentVault without reentrancy protection. This created a potential attack vector where a malicious token contract or compromised external contract could re-enter the execute function during token transfers or swaps, potentially manipulating state or draining funds.

**Resolution:**
- Implemented comprehensive `ReentrancyGuard` contract following industry best practices
- Added `nonReentrant` modifier to the `execute` function in SwapAction
- All external calls are now protected by the reentrancy guard:
  1. ERC20 token transfers (`transferFrom`)
  2. Uniswap router swap execution
  3. IntentVault spending recording
- Added `SwapExecuted` event for better tracking and transparency
- Enhanced input validation (token addresses, amounts, deadline)
- Improved error messages with contract-specific prefixes
- Added comprehensive inline documentation explaining the protection

**Technical Details:**
The ReentrancyGuard uses a state variable that tracks whether a function is currently executing. The `nonReentrant` modifier sets this state to "ENTERED" before function execution and resets it to "NOT_ENTERED" after completion. Any attempt to re-enter while the state is "ENTERED" will cause the transaction to revert.

**Impact:**
Users are now protected from reentrancy attacks during token swaps. The contract follows the checks-effects-interactions pattern and prevents recursive calls that could compromise the integrity of swap operations.

**Recommendation for Existing Deployments:**
If you have already deployed SwapAction without reentrancy protection:
1. Deploy the updated version immediately
2. Update FlowExecutor to use the new SwapAction address
3. Deprecate the old SwapAction contract
4. Monitor all swap transactions for any anomalies

## Reporting a Vulnerability

If you discover a security vulnerability, please email security@labi.protocol with:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if available)

We aim to respond to security reports within 48 hours.
