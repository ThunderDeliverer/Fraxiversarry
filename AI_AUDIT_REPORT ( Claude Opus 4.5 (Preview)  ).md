# Fraxiversarry Smart Contract Security Audit Report

**Project:** Fraxiversarry NFT Collection  
**Auditor:** Security Review  
**Date:** December 9, 2025  
**Commit:** Current working tree  
**Scope:** `src/Fraxiversarry.sol`, `src/FraxiversarryEthereum.sol`, and related interfaces  

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Scope](#scope)
3. [Methodology](#methodology)
4. [Findings Summary](#findings-summary)
5. [Detailed Findings](#detailed-findings)
   - [Critical](#critical)
   - [High](#high)
   - [Medium](#medium)
   - [Low](#low)
   - [Informational](#informational)
6. [Gas Optimizations](#gas-optimizations)
7. [Test Coverage Analysis](#test-coverage-analysis)
8. [Recommendations](#recommendations)
9. [Conclusion](#conclusion)

---

## Executive Summary

This report presents the findings of a security audit conducted on the Fraxiversarry smart contracts. The Fraxiversarry project is an ERC721 NFT collection celebrating the 5th anniversary of Frax Finance, featuring:

- **Multiple token types:** BASE, GIFT, FUSED, and SOULBOUND
- **ERC20 tokenization:** NFTs are backed by deposited ERC20 tokens (IERC7590)
- **Soulbound mechanics:** Non-transferable tokens (IERC6454)
- **Cross-chain support:** LayerZero ONFT721 integration for bridging
- **Token fusion:** Ability to combine 4 BASE tokens into a FUSED premium token

### Risk Assessment

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 2 |
| Medium | 4 |
| Low | 5 |
| Informational | 6 |

### Overall Assessment

The codebase demonstrates **solid Solidity practices** with comprehensive test coverage. The contracts are well-documented with clear NatSpec comments. The `burn()` function correctly follows the Checks-Effects-Interactions pattern within `_transferHeldERC20FromToken()`, updating balances before external calls. Some security concerns require attention before mainnet deployment, particularly around **cross-chain message validation** and **ERC20 compatibility**.

---

## Scope

### Contracts Reviewed

| Contract | Lines of Code | Description |
|----------|---------------|-------------|
| `Fraxiversarry.sol` | ~800 | Main NFT contract (Fraxtal deployment) |
| `FraxiversarryEthereum.sol` | ~300 | Ethereum mirror for cross-chain bridging |
| `IFraxiversarryErrors.sol` | ~80 | Custom error definitions |
| `IFraxiversarryEvents.sol` | ~100 | Event definitions |
| `IERC6454.sol` | ~20 | Soulbound token interface |
| `IERC7590.sol` | ~60 | ERC20 holder token interface |

### External Dependencies

- OpenZeppelin Contracts v5.x (ERC721, Pausable, Ownable)
- LayerZero V2 ONFT-EVM Contracts

---

## Methodology

The audit was conducted using the following methodology:

1. **Manual Code Review:** Line-by-line analysis of smart contract code
2. **Static Analysis:** Pattern matching for common vulnerabilities
3. **Test Review:** Analysis of existing test coverage
4. **Architecture Review:** Evaluation of contract interactions and data flows
5. **Cross-chain Analysis:** Review of ONFT bridging mechanics

---

## Findings Summary

| ID | Title | Severity | Status |
|----|-------|----------|--------|
| H-01 | Missing peer validation in cross-chain receive | High | Open |
| H-02 | Non-standard ERC20 return values not handled | High | Open |
| M-01 | Arbitrary token URI injection via bridge | Medium | Open |
| M-02 | DoS risk in `retrieveCollectedFees()` | Medium | Open |
| M-03 | FUSED token custody uses `_update` directly | Medium | Open |
| M-04 | Soulbound tokens can be bridge-burned | Medium | Open |
| L-01 | Missing zero-address validation in constructor | Low | Open |
| L-02 | Hardcoded 2-second block time assumption | Low | Open |
| L-03 | `burn()` removes standard approval check | Low | Open |
| L-04 | Fragile FUSED token detection in URI refresh | Low | Open |
| L-05 | Missing event for admin URI updates | Low | Open |
| I-01 | TODO comment left in production code | Informational | Open |
| I-02 | Error interface declared as contract | Informational | Open |
| I-03 | IERC7590 functions always revert by design | Informational | Open |
| I-04 | Unused parameters in `isTransferable()` | Informational | Open |
| I-05 | Assembly block for message parsing | Informational | Open |
| I-06 | Ethereum contract missing documentation | Informational | Open |

---

## Detailed Findings

### Critical

*No critical findings.*

> **Note:** Initial analysis flagged a potential reentrancy issue in `burn()`. Upon closer review, the `_transferHeldERC20FromToken()` function correctly follows the Checks-Effects-Interactions (CEI) pattern:
> 1. **Check:** Verifies sufficient balance
> 2. **Effect:** Updates `erc20Balances[_tokenId][_erc20Contract] -= _amount` and increments nonce
> 3. **Interaction:** External `transfer()` call happens last
> 
> Even if a malicious ERC20 re-enters during the transfer, each asset's balance is already zeroed, preventing double-spending.

---

### High

#### H-01: Missing Peer Validation in Cross-Chain Receive

**Severity:** High  
**Location:** `Fraxiversarry.sol:721-768` (`_lzReceive`)  
**Status:** Open

**Description:**

The `_lzReceive()` function processes incoming cross-chain messages without explicitly validating that the source originates from a trusted peer contract. While LayerZero's OApp framework includes peer validation in the base layer, the contract does not configure or verify peers explicitly.

```solidity
function _lzReceive(
    Origin calldata _origin,
    bytes32 _guid,
    bytes calldata _message,
    address _executor,
    bytes calldata _executorData
) internal override {
    address toAddress = _message.sendTo().bytes32ToAddress();
    uint256 tokenId = _message.tokenId();
    
    // ❌ No explicit validation of _origin.srcEid or _origin.sender
    // ...
    _credit(toAddress, tokenId, _origin.srcEid);
    _setTokenURI(tokenId, tokenUri);
    isNonTransferrable[tokenId] = isSoulbound;
}
```

**Impact:**

- If LayerZero configuration is incorrect, unauthorized sources could mint tokens
- Attackers could potentially credit tokens to arbitrary addresses
- Token URIs and soulbound flags could be set maliciously

**Recommendation:**

Ensure proper peer configuration and add explicit validation:

```solidity
function _lzReceive(...) internal override {
    // Verify sender is a known peer
    bytes32 expectedPeer = peers[_origin.srcEid];
    if (expectedPeer == bytes32(0) || expectedPeer != _origin.sender) {
        revert UnauthorizedPeer();
    }
    // ... rest of implementation
}
```

---

#### H-02: Non-Standard ERC20 Return Values Not Handled

**Severity:** High  
**Location:** `Fraxiversarry.sol:645-663` (`_transferERC20ToToken`)  
**Status:** Open

**Description:**

The contract checks ERC20 transfer return values with boolean checks:

```solidity
if (!erc20Token.transferFrom(_from, address(this), amountWithFee)) revert TransferFailed();
```

However, some widely-used ERC20 tokens (notably USDT on Ethereum mainnet) do not return a boolean value, which would cause these calls to revert unexpectedly.

**Impact:**

- Tokens like USDT cannot be used as underlying assets
- User transactions may fail unexpectedly
- Limits ecosystem compatibility

**Recommendation:**

Use OpenZeppelin's SafeERC20 library:

```solidity
import {SafeERC20} from "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";

contract Fraxiversarry is ... {
    using SafeERC20 for IERC20;
    
    function _transferERC20ToToken(...) internal {
        IERC20 erc20Token = IERC20(_erc20Contract);
        // ...
        erc20Token.safeTransferFrom(_from, address(this), amountWithFee);
        // ...
    }
    
    function _transferHeldERC20FromToken(...) internal {
        IERC20 erc20Token = IERC20(_erc20Contract);
        // ...
        erc20Token.safeTransfer(_to, _amount);
        // ...
    }
}
```

---

### Medium

#### M-01: Arbitrary Token URI Injection via Bridge

**Severity:** Medium  
**Location:** `Fraxiversarry.sol:755`  
**Status:** Open

**Description:**

During cross-chain receive, the token URI from the composed message is applied directly without validation:

```solidity
(string memory tokenUri, bool isSoulbound) = abi.decode(rawMessage, (string, bool));
_credit(toAddress, tokenId, _origin.srcEid);
_setTokenURI(tokenId, tokenUri);  // ❌ No validation
isNonTransferrable[tokenId] = isSoulbound;
```

**Impact:**

- Malformed or malicious URIs could be set
- Phishing URIs could be injected if bridge is compromised
- Inconsistent metadata across chains

**Recommendation:**

Consider maintaining a registry of valid URI prefixes or implementing URI format validation.

---

#### M-02: DoS Risk in `retrieveCollectedFees()`

**Severity:** Medium  
**Location:** `Fraxiversarry.sol:444-452`  
**Status:** Open

**Description:**

If a supported ERC20 token becomes malicious (e.g., starts reverting on all transfers), the accumulated fees for that token become permanently stuck.

```solidity
function retrieveCollectedFees(address _erc20Contract, address _to) public onlyOwner {
    uint256 feeAmount = collectedFees[_erc20Contract];
    if (feeAmount == 0) return;
    
    collectedFees[_erc20Contract] = 0;
    if (!IERC20(_erc20Contract).transfer(_to, feeAmount)) revert TransferFailed();
    // ❌ If transfer reverts, fees are stuck
}
```

**Recommendation:**

Add a rescue function for stuck tokens:

```solidity
function rescueStuckTokens(address token, address to, uint256 amount) external onlyOwner {
    IERC20(token).transfer(to, amount);
}
```

---

#### M-03: FUSED Token Custody Uses `_update` Directly

**Severity:** Medium  
**Location:** `Fraxiversarry.sol:568-571`  
**Status:** Open

**Description:**

The `fuseTokens()` function transfers BASE tokens into the contract using `_update()` directly:

```solidity
_update(address(this), _tokenId1, msg.sender);
_update(address(this), _tokenId2, msg.sender);
_update(address(this), _tokenId3, msg.sender);
_update(address(this), _tokenId4, msg.sender);
```

While this works, it bypasses `_safeTransfer` which checks that the receiver can handle ERC721 tokens.

**Recommendation:**

Document this design decision clearly or use `safeTransferFrom` for clarity.

---

#### M-04: Soulbound Tokens Can Be Bridge-Burned

**Severity:** Medium  
**Location:** `Fraxiversarry.sol:673-678`  
**Status:** Open

**Description:**

Soulbound tokens cannot be transferred normally, but they CAN be bridged to another chain:

```solidity
function _bridgeBurn(address _owner, uint256 _tokenId) internal {
    _isBridgeOperation = true;
    _update(address(0), _tokenId, _owner);  // Bypasses soulbound check
    _isBridgeOperation = false;
}
```

This may be intentional, but it weakens the soulbound guarantee.

**Recommendation:**

Either:
1. Document that soulbound tokens are bridgeable by design, OR
2. Prevent bridging of soulbound tokens:

```solidity
function _debit(address _from, uint256 _tokenId, uint32 _dstEid) internal override {
    if (isNonTransferrable[_tokenId]) revert CannotBridgeSoulboundToken();
    // ...
}
```

---

### Low

#### L-01: Missing Zero-Address Validation in Constructor

**Severity:** Low  
**Location:** `Fraxiversarry.sol:160-179`  
**Status:** Open

**Description:**

The constructor does not validate that `_initialOwner` and `_lzEndpoint` are non-zero addresses.

**Recommendation:**

```solidity
constructor(address _initialOwner, address _lzEndpoint) ... {
    if (_initialOwner == address(0)) revert ZeroAddress();
    if (_lzEndpoint == address(0)) revert ZeroAddress();
    // ...
}
```

---

#### L-02: Hardcoded 2-Second Block Time Assumption

**Severity:** Low  
**Location:** `Fraxiversarry.sol:175`  
**Status:** Open

**Description:**

```solidity
mintingCutoffBlock = block.number + (35 days / 2 seconds);
```

This assumes a fixed 2-second block time for Fraxtal. If block times change, the actual minting period will differ from the intended ~5 weeks.

**Recommendation:**

Consider using `block.timestamp` for time-based cutoffs:

```solidity
mintingCutoffTimestamp = block.timestamp + 35 days;
```

---

#### L-03: `burn()` Removes Standard Approval Check

**Severity:** Low  
**Location:** `Fraxiversarry.sol:253`  
**Status:** Open

**Description:**

The standard `ERC721Burnable.burn()` allows approved operators to burn tokens. The override restricts this to only the owner:

```solidity
if (msg.sender != ownerOf(_tokenId)) revert OnlyTokenOwnerCanBurnTheToken();
```

**Recommendation:**

If intentional, document this. Otherwise, restore:

```solidity
if (!_isAuthorized(ownerOf(_tokenId), msg.sender, _tokenId)) {
    revert OnlyTokenOwnerCanBurnTheToken();
}
```

---

#### L-04: Fragile FUSED Token Detection in URI Refresh

**Severity:** Low  
**Location:** `Fraxiversarry.sol:344-348`  
**Status:** Open

**Description:**

```solidity
if (underlyingTokenIds[tokenId][0] != 0 || underlyingTokenIds[tokenId][1] != 0) {
    _setTokenURI(tokenId, premiumTokenUri);
}
```

This relies on underlying token IDs being non-zero. If token ID 0 is ever used, this logic could fail.

**Recommendation:**

Use explicit type checking:

```solidity
if (tokenTypes[tokenId] == TokenType.FUSED) {
    _setTokenURI(tokenId, premiumTokenUri);
}
```

---

#### L-05: Missing Event for Admin URI Updates

**Severity:** Low  
**Location:** `Fraxiversarry.sol:359-366`  
**Status:** Open

**Description:**

The `updateSpecificTokenUri()` function relies on `MetadataUpdate` from `_setTokenURI()` but doesn't emit an admin-specific event for tracking purposes.

**Recommendation:**

Add an event:

```solidity
event TokenUriUpdatedByAdmin(uint256 indexed tokenId, string newUri);
```

---

### Informational

#### I-01: TODO Comment Left in Production Code

**Location:** `Fraxiversarry.sol:177-179`

```solidity
//TODO: Set correct URIs
giftTokenUri = "https://gift.tba.frax/";
premiumTokenUri = "https://premium.tba.frax/";
```

**Recommendation:** Remove TODO comments and set correct URIs before deployment.

---

#### I-02: Error Interface Declared as Contract

**Location:** `IFraxiversarryErrors.sol`

The errors are declared in a `contract` rather than an `interface`, which is unconventional.

**Recommendation:** Use `interface IFraxiversarryErrors` for clarity.

---

#### I-03: IERC7590 Functions Always Revert by Design

**Location:** `Fraxiversarry.sol:485-502`

The `transferHeldERC20FromToken()` and `transferERC20ToToken()` functions always revert.

**Recommendation:** Add clear NatSpec documentation explaining this is by design.

---

#### I-04: Unused Parameters in `isTransferable()`

**Location:** `Fraxiversarry.sol:467-469`

The `_from` and `_to` parameters are unused but required for IERC6454 compliance.

**Recommendation:** This is acceptable; consider adding a comment for clarity.

---

#### I-05: Assembly Block for Message Parsing

**Location:** `Fraxiversarry.sol:741-750`

Assembly is used for slicing the composed message. While correct, this increases complexity.

**Recommendation:** Consider using a helper library if gas permits, or add detailed comments.

---

#### I-06: Ethereum Contract Missing Documentation

**Location:** `FraxiversarryEthereum.sol`

The Ethereum contract is a stripped-down mirror lacking many features of the main contract.

**Recommendation:** Add clear documentation explaining this is a bridge-only mirror.

---

## Gas Optimizations

| ID | Description | Savings Estimate |
|----|-------------|------------------|
| G-01 | Cache `underlyingAssets[_tokenId][i]` in burn loop | ~200 gas per asset |
| G-02 | Use `unchecked` increment in all loops | ~20 gas per iteration |
| G-03 | Pack storage variables where possible | Variable |
| G-04 | Use `calldata` instead of `memory` for string params | ~100 gas per call |

---

## Test Coverage Analysis

### Coverage Summary

The test suite includes comprehensive coverage across:

| Category | Coverage |
|----------|----------|
| Token Minting (BASE, GIFT, SOULBOUND) | ✅ Excellent |
| Token Burning | ✅ Good |
| Fuse/Unfuse Operations | ✅ Excellent |
| Fee Collection | ✅ Good |
| Soulbound Restrictions | ✅ Excellent |
| ONFT Bridging | ✅ Good |
| Pause Functionality | ✅ Good |
| URI Management | ✅ Good |
| Edge Cases | ✅ Good |

### Missing Test Coverage

| Area | Description |
|------|-------------|
| Malicious ERC20 | Limited testing with callback tokens |
| Peer Validation | No tests for cross-chain authorization |
| Concurrent Bridge | No multi-chain state synchronization tests |

---

## Recommendations

### Immediate Actions (Pre-Deployment)

1. **[HIGH]** Implement SafeERC20 for all token transfers
2. **[HIGH]** Verify and test LayerZero peer configuration
3. **[MEDIUM]** Remove TODO comments and set production URIs

### Short-Term Improvements

4. Add zero-address validation in constructor
5. Consider timestamp-based minting cutoff
6. Document soulbound bridging behavior
7. Add rescue function for stuck tokens

### Long-Term Enhancements

8. Consider formal verification for critical functions
9. Implement additional cross-chain state validation
10. Add monitoring and alerting for bridge operations

---

## Conclusion

The Fraxiversarry smart contracts demonstrate **solid engineering practices** with well-structured code, comprehensive documentation, and extensive test coverage. The implementation correctly combines multiple complex features including ERC721 extensions, ERC20 tokenization, soulbound mechanics, and cross-chain bridging.

Notably, the `burn()` function correctly implements the Checks-Effects-Interactions pattern within `_transferHeldERC20FromToken()`, updating balances before external calls - an important security consideration that was properly addressed.

The **High-severity issues** around ERC20 handling and cross-chain validation should be addressed before mainnet deployment.

### Risk Matrix

| Risk Level | Finding Count | Mitigation Priority |
|------------|---------------|---------------------|
| Critical | 0 | N/A |
| High | 2 | Before Deployment |
| Medium | 4 | Before Deployment |
| Low | 5 | Post-Deployment OK |
| Informational | 6 | Optional |

### Final Recommendation

Address High and Medium severity issues before mainnet deployment. After fixes are implemented, a follow-up review is recommended to verify the changes.

---

## Appendix

### A. Files Reviewed

```
src/
├── Fraxiversarry.sol
├── FraxiversarryEthereum.sol
└── interfaces/
    ├── IERC6454.sol
    ├── IERC7590.sol
    ├── IFraxiversarryErrors.sol
    └── IFraxiversarryEvents.sol

test/
├── Fraxiversarry.t.sol
├── FraxiversarryEthereum.t.sol
├── FraxiversarryOFT.t.sol
└── mocks/
    ├── MockERC20.sol
    ├── MockLzEndpoint.sol
    └── MockMsgInspector.sol
```

### B. Tools Used

- Manual Code Review
- Foundry Test Suite Analysis
- Static Analysis Patterns

### C. Disclaimer

This audit report is provided on an "as-is" basis. The findings are based on the code state at the time of review. Changes made after this review may introduce new vulnerabilities. This report does not guarantee the absence of all security issues.

---

**End of Report**
