# erc4626-vault

A multi-file, ERC-4626-style token vault built with Foundry. Depositors pool one ERC-20 (the asset) and receive shares; the share price rises when yield is sent to the vault.

> **Not audited.** This is a learning project written as if it were going to production. Do not use it with real funds.

## Status

Work in progress (Week 3 of a one-project-per-week series). Sections marked **TODO** are written by the author as each stage is finished.

## Layout

```
src/
  interfaces/IVault.sol     public surface: signatures, events, custom errors
  libraries/VaultMath.sol   pure share/asset conversions with explicit rounding
  Vault.sol                 state, deposit, redeem, admin controls
test/                       unit, fuzz, invariant, attack, mocks
script/                     deploy script and per-chain config
```

## How to run

```shell
git clone --recurse-submodules https://github.com/Nuelverse/erc4626-vault.git
cd erc4626-vault
forge build
forge test
forge fmt --check
```

Solidity 0.8.28 (pinned in `foundry.toml`), OpenZeppelin Contracts v5.7.0.

## Design

> This section describes the intended design. It is written before the code, and every claim here must be backed by a test before the project is finished.

### What each file does

| File | Job |
|---|---|
| `src/interfaces/IVault.sol` | The public surface: function signatures, events and custom errors. |
| `src/libraries/VaultMath.sol` | Pure share/asset conversions with an explicit rounding direction. No state. |
| `src/Vault.sol` | State, `deposit`, `redeem` and the admin controls. |

### State

| Variable | Meaning | Who can change it |
|---|---|---|
| `asset` | The ERC-20 being pooled | Nobody. It is `immutable`, set in the constructor. |
| Deposit cap | Maximum total assets the vault accepts | Owner |
| Paused flag | Whether new deposits are blocked | Owner |
| Owner | The admin address | Two-step transfer (current owner proposes, new owner accepts) |
| Share balances | Who holds how many shares (the vault is itself an ERC-20) | Deposits, redemptions and ordinary share transfers |

### Functions

| Function | Who can call | What it does |
|---|---|---|
| `deposit(assets, receiver)` | Anyone, while not paused and under the cap | The caller pays; `receiver` (any address) gets the shares. |
| `redeem(shares, receiver, owner)` | The share owner, or a spender holding enough share allowance from the owner. Always works, even when paused. | Burns the owner's shares and sends assets to `receiver` (any address). |
| `asset`, `totalAssets`, `convertToShares`, `convertToAssets` | Anyone (views) | Reads. |
| `pause`, `unpause`, `setDepositCap` | Owner only | Controls new deposits only. |
| `transferOwnership`, `acceptOwnership` | Owner proposes, new owner accepts | Two-step ownership change. |

### Decisions

1. **The asset cannot change.** If the owner could swap it, `totalAssets` would read a different token's balance and every share would be priced against money nobody deposited.
2. **`totalAssets` reads the real token balance**, not a stored counter. Tokens sent straight to the vault raise the price of every share, which is how yield reaches holders with no per-person bookkeeping. The cost is that anyone can also move the price by donating, which is the root of the inflation attack described below.
3. **Rounding always favours the vault.** Shares minted on deposit round down, and assets paid on redeem round down. The depositor never receives more than they put in.
4. **A deposit that would mint zero shares reverts**, rather than taking the caller's tokens for nothing.
5. **Deposits measure what the vault actually received** (balance after minus balance before), never the `assets` argument, so fee-on-transfer tokens cannot cause over-minting.
6. **Redeeming for someone else uses the ordinary share allowance.** An approval of `type(uint256).max` is treated as unlimited and is never reduced, so a user who approves a spender for the maximum has given that spender permanent control of their shares until they reset it to 0.
7. **Pausing blocks `deposit` only.** `redeem` has no pause check.
8. **The interface declares only the vault's own surface.** `transferOwnership` and `acceptOwnership` come from OpenZeppelin `Ownable2Step` and are not redeclared in `IVault`. Errors that OpenZeppelin already defines (`EnforcedPause`, `OwnableUnauthorizedAccount`, `ERC20InsufficientAllowance`, `ERC20InsufficientBalance`) are inherited, not duplicated.
9. **Errors carry the numbers needed to debug a failure.** `DepositCapExceeded` reports the attempted amount and the room left under the cap (0 if the vault is already at or above it).
10. **`deposit` and `redeem` emit the standard `Deposit` and `Withdraw` events**, so wallets and indexers recognise them.

Open decisions, to be filled in as the stages are completed:

- What happens to existing depositors if the owner sets the cap below the current total assets.
- Which defense is used against the inflation attack, and what it costs.

## Owner powers

The owner's power is exactly the list of `onlyOwner` functions. None of them moves tokens.

**The owner can:**
- pause and unpause new deposits
- set the deposit cap
- start a transfer of ownership (the new owner must accept it)

**The owner cannot:**
- withdraw, move, freeze or redirect user funds
- block `redeem`, including while the vault is paused
- change the asset
- mint shares or change anyone's share balance

**If the owner key is stolen**, the worst case is that new deposits are stopped and the key is passed to the attacker. Existing holders can still redeem. These claims are only real once Stage 5 tests prove them.

## Inflation attack: test and defense

TODO: the attack on the naive version, the chosen defense, and what it costs.

## Threat model

TODO

## Known limitations

TODO

## License

MIT, see [LICENSE](LICENSE).
