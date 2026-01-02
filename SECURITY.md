# Security Policy

## Security Updates

### [2026-01-02] Slippage Validation for SwapAction Contract

**Issue:** Missing slippage validation in SwapAction contract (Issue #6)

**Severity:** High

**Description:**
The SwapAction contract accepted `amountOutMin` from user input without validating whether it was reasonable. Users could set this value to 0 or dangerously low amounts, exposing them to:
- MEV (Maximal Extractable Value) attacks
- Sandwich attacks
- Excessive slippage losses
- Front-running attacks

The lack of validation meant users could unknowingly approve swaps that would result in receiving far less than expected, with attackers able to extract significant value.

**Resolution:**
- Implemented configurable minimum slippage tolerance (default: 0.5%)
- Added configurable maximum slippage bounds (default: 5%)
- Enforced validation: user's `amountOutMin` must meet minimum slippage requirements
- Added `SlippageProtectionTriggered` event when protection is activated
- Implemented owner-only functions to configure slippage parameters:
  - `setMinSlippage(uint256)` - Set minimum slippage tolerance
  - `setMaxSlippage(uint256)` - Set maximum slippage tolerance
- Added helper functions:
  - `getSlippageConfig()` - View current configuration
  - `calculateMinOutput(uint256)` - Calculate minimum output for given input
- Used basis points (bp) for precision: 10000 bp = 100%

**Technical Implementation:**
```solidity
// Calculate minimum acceptable output
uint256 calculatedMinOutput = (amountIn * (10000 - minSlippageBps)) / 10000;

// Reject if user's amountOutMin is too low
if (amountOutMin < calculatedMinOutput) {
    emit SlippageProtectionTriggered(vault, amountIn, amountOutMin, calculatedMinOutput);
    revert("SwapAction: slippage tolerance too high");
}
```

**Example:**
- Input: 1000 tokens
- Minimum slippage: 50 bp (0.5%)
- Calculated minimum output: 995 tokens
- If user sets amountOutMin < 995, transaction reverts

**Impact:**
Users are now protected from:
- Accidentally setting zero or very low slippage tolerance
- MEV bot exploitation
- Sandwich attacks that would result in significant value loss
- Front-running with excessive slippage

**Default Configuration:**
- Minimum slippage: 50 basis points (0.5%)
- Maximum slippage: 500 basis points (5%)
- Basis points denominator: 10000 (100%)

**Recommendation for Existing Deployments:**
If you have already deployed SwapAction without slippage validation:
1. Deploy the updated version immediately
2. Configure appropriate slippage parameters for your use case
3. Update FlowExecutor to use the new SwapAction address
4. Deprecate the old SwapAction contract
5. Monitor SlippageProtectionTriggered events to understand user behavior

**Future Enhancements:**
- Integration with price oracles for dynamic slippage calculation
- Different slippage tolerances for different token pairs
- Automatic slippage adjustment based on market volatility

## Reporting a Vulnerability

If you discover a security vulnerability, please email security@labi.protocol with:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if available)

We aim to respond to security reports within 48 hours.
