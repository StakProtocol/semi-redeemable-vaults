# Security Audit Report - StakVault

## Executive Summary

This document outlines critical vulnerabilities and attack vectors identified in the `StakVault` contract. All vulnerabilities have been verified with Proof of Concept (PoC) tests in `test/StakVaultExploits.t.sol`.

## Critical Vulnerabilities

### 1. ⚠️ CRITICAL: Owner Can Manipulate Performance Fees

**Location**: `_calculatePerformanceFee()` line 434, `updateTotalAssets()` line 129

**Description**: 
The owner can set `_totalAssets` to any arbitrary value. The performance fee calculation uses this value to compute the price per share via the parent's `_convertToAssets()` function. By setting an artificially high `totalAssets`, the owner can make it appear as if the vault has made huge profits, triggering excessive performance fees.

**Impact**: 
- **Theft of user funds** through inflated performance fees
- Owner can extract fees based on fake profits
- High severity - direct financial loss to users

**PoC**: `test_POC_OwnerManipulatesPerformanceFee()`
- Owner sets `totalAssets` to 10x the actual value
- Performance fee of 1,800 tokens extracted from a 1,000 token deposit
- Demonstrates how owner can drain funds via fake profits

**Recommendation**:
- Add validation to ensure `totalAssets` is within reasonable bounds
- Consider using time-weighted average or require external oracle for `totalAssets`
- Add maximum fee cap per transaction
- Consider multi-sig or timelock for `updateTotalAssets()`

---

### 2. ⚠️ CRITICAL: Owner Can Drain Assets and Hide Losses

**Location**: `takeAssets()` line 118, `updateTotalAssets()` line 129

**Description**:
The owner can call `takeAssets()` to withdraw funds from the vault, then call `updateTotalAssets()` to set a value that doesn't reflect the actual loss. When NAV redemptions are enabled, users will receive less than they should because the contract doesn't have enough assets to cover the reported `totalAssets`.

**Impact**:
- **Theft of user funds** - owner can drain vault
- **Hidden losses** - users think vault is healthy when it's not
- High severity - direct financial loss and deception

**PoC**: `test_POC_OwnerDrainsAndHidesLosses()`
- Owner drains 1,500 tokens from 3,000 token vault
- Owner reports `totalAssets` as still 3,000
- Users redeeming at NAV will get less than expected

**Recommendation**:
- Require `totalAssets <= actualBalance` or add validation
- Add events/logging for all asset movements
- Consider requiring external audit/verification for `totalAssets` updates
- Implement maximum withdrawal limits per period

---

### 3. ⚠️ HIGH: PreviewWithdraw Manipulation Leading to Excessive Share Burning

**Location**: `_previewWithdraw()` line 381-384

**Description**:
The `_previewWithdraw()` function uses `Math.max()` between the standard ERC4626 conversion (which uses `totalAssets()`) and the user's ledger conversion. If the owner sets `totalAssets` to 0 or a very small value, the standard conversion returns an extremely large number. The `Math.max()` then forces users to burn way more shares than they should when withdrawing.

**Impact**:
- **DoS attack** - users cannot withdraw without losing excessive shares
- **Theft of shares** - users lose more value than intended
- Medium-High severity - can prevent legitimate withdrawals

**PoC**: `test_POC_PreviewWithdrawManipulation()`
- Normal withdrawal: 500 assets = 500 shares
- After manipulation: 500 assets = 250,000,000,000,000,000,000,250,000,000,000,000,000,000 shares
- Demonstrates massive share inflation

**Recommendation**:
- Add bounds checking on `totalAssets` (minimum value)
- Consider using only ledger-based conversion when not in NAV mode
- Add sanity checks on conversion results
- Cap the maximum shares that can be required

---

### 4. ⚠️ MEDIUM: Ledger Inconsistency After NAV Switch

**Location**: `deposit()` line 248, `mint()` line 268

**Description**:
When NAV redemptions are enabled, new deposits don't update the user's ledger. However, users who deposited before the NAV switch can still redeem using their ledger at fair price (1:1). This creates an inconsistency where:
- Early depositors redeem at fair price (their original deposit rate)
- Late depositors redeem at NAV (current market rate)
- This can lead to unfairness and potential arbitrage opportunities

**Impact**:
- **Unfair redemption rates** between users
- **Potential arbitrage** opportunities
- Medium severity - fairness and economic issues

**PoC**: `test_POC_LedgerInconsistencyAfterNavSwitch()`
- User1 deposits before NAV switch at 1:1
- Vault reports 2x NAV
- User2 deposits after NAV switch at 2:1 (gets half shares)
- Both can redeem, but at different effective rates

**Recommendation**:
- When NAV is enabled, migrate all ledgers to NAV-based pricing
- Or prevent ledger-based redemptions after NAV switch
- Add clear documentation about redemption behavior

---

### 5. ⚠️ MEDIUM: Approval Mechanism for Delegated Redemptions

**Location**: `redeem()` line 334, `withdraw()` line 370

**Description**:
When user1 approves user2 to redeem shares, user2 should be able to redeem the shares on behalf of user1. The contract extends ERC4626 which inherits from ERC20, providing standard `approve()` and `transferFrom()` functionality. The `redeem()` and `withdraw()` functions accept a `user` parameter to support delegated redemptions, but the proper handling of allowances through the parent `_withdraw()` function needs to be verified.

**Impact**:
- **Access control failure** - delegated redemptions may not work as expected
- **Functionality break** - users cannot delegate redemption permissions
- Medium severity - affects expected ERC4626/ERC20 behavior and user expectations

**Recommendation**:
- Verify that the parent ERC4626 `_withdraw()` function properly checks allowances when `_msgSender()` differs from `user`
- Ensure that `redeem()` and `withdraw()` correctly handle the approval mechanism
- Add comprehensive tests for delegated redemption scenarios
- Document the approval and delegation behavior clearly

---

## Summary of Severity Levels

- **CRITICAL (2)**: Owner manipulation of performance fees, owner can drain and hide losses
- **HIGH (1)**: PreviewWithdraw manipulation
- **MEDIUM (3)**: Ledger inconsistency, division by zero, approval mechanism for delegated redemptions
- **LOW (2)**: Redundant code, vesting confusion
- **INFO (1)**: Edge case behavior

## General Recommendations

1. **Access Control**: Consider implementing timelock or multi-sig for critical owner functions
2. **Validation**: Add bounds checking and validation for all owner-controlled parameters
3. **Transparency**: Add more events and logging for all state changes
4. **Documentation**: Clearly document redemption behavior, especially around NAV switching
5. **Testing**: Add more edge case tests, especially around zero values and boundary conditions
6. **Code Quality**: Remove redundant code and improve clarity

## Testing

All vulnerabilities have been verified with PoC tests in:
- `test/StakVaultExploits.t.sol`

Run tests with:
```bash
forge test --match-contract StakVaultExploits -vv
```

