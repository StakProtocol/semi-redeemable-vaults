# StakVault

An ERC-4626 vault with dual redemption modes and per-user deposit tracking.

## Features

- **Dual Redemption Modes**
  - NAV Mode: Standard ERC-4626 redemption at current Net Asset Value
  - Deposit Price Mode: Redemption at original deposit price using per-user ledger

- **Per-User Ledger System**: Tracks individual user deposits (assets & shares) for fair redemption pricing

- **Owner Controls**: Set total assets externally and toggle between redemption modes

## Installation

```bash
forge soldeer install
forge build
```

## Usage

### Deploy

```solidity
StakVault vault = new StakVault(
    assetToken,
    "Vault Token",
    "VAULT",
    owner
);
```

### Owner Operations

```solidity
vault.setTotalAssets(newTotalAssets);
vault.setRedeemsAtNav();
```

## Testing

```bash
forge test
```

## License

MIT
