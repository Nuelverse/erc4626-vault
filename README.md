# erc4626-vault

A multi-file, ERC-4626-style token vault built with Foundry. Depositors pool one ERC-20 (the asset) and receive shares; the share price rises when yield is sent to the vault.

> **Not audited.** This is a learning project written as if it were going to production. Do not use it with real funds.

## Status

Work in progress (Week 3 of a one-project-per-week series). The contracts, the unit tests and the inflation-attack test are done. Still to do: fuzz and invariant tests at the vault level, a reentrancy test with a malicious token, the deploy script and CI. See [Tests](#tests) for exactly what is and is not covered.

## Layout

```
src/
  interfaces/IVault.sol     public surface: signatures, events, custom errors
  libraries/VaultMath.sol   pure share/asset conversions with explicit rounding
  Vault.sol                 state, deposit, redeem, admin controls
test/
  unit/                     VaultMath and Vault unit tests
  attack/                   the inflation-attack tests
  mocks/                    MockERC20, MockFeeToken (takes a 10% fee on every transfer)
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
| `depositCap` | Maximum total assets the vault accepts | Owner |
| Paused flag | Whether new deposits are blocked | Owner |
| Owner | The admin address | Two-step transfer (current owner proposes, new owner accepts) |
| Share balances | Who holds how many shares (the vault is itself an ERC-20) | Deposits, redemptions and ordinary share transfers |
| Locked shares | 1,000 shares held by `0x000000000000000000000000000000000000dEaD` since the first deposit | Nobody. See [the defense](#the-defense-lock-the-first-1000-shares). |

### Functions

| Function | Who can call | What it does |
|---|---|---|
| `deposit(assets, receiver)` | Anyone, while not paused and under the cap | The caller pays; `receiver` (any address) gets the shares. |
| `redeem(shares, receiver, owner)` | The share owner, or a spender holding enough share allowance from the owner. Always works, even when paused. | Burns the owner's shares and sends assets to `receiver`. `receiver` cannot be the zero address. |
| `asset`, `totalAssets`, `convertToShares`, `convertToAssets` | Anyone (views) | Reads. |
| `pause`, `unpause`, `setDepositCap` | Owner only | Controls new deposits only. |
| `transferOwnership`, `acceptOwnership` | Owner proposes, new owner accepts | Two-step ownership change. |
| `renounceOwnership` | Owner | Always reverts. Ownership can only move to a new owner. |

### Decisions

1. **The asset cannot change.** If the owner could swap it, `totalAssets` would read a different token's balance and every share would be priced against money nobody deposited.
2. **`totalAssets` reads the real token balance**, not a stored counter. Tokens sent straight to the vault raise the price of every share, which is how yield reaches holders with no per-person bookkeeping. The cost is that anyone can also move the price by donating, which is the root of the inflation attack described below.
3. **Rounding always favours the vault.** Shares minted on deposit round down, and assets paid on redeem round down. The depositor never receives more than they put in.
4. **A deposit that would mint zero shares reverts**, rather than taking the caller's tokens for nothing. The same goes for a redeem that would pay zero assets.
5. **Deposits measure what the vault actually received** (balance after minus balance before), never the `assets` argument, so fee-on-transfer tokens cannot cause over-minting. The same measured amount is used for the cap check.
6. **Redeeming for someone else uses the ordinary share allowance.** An approval of `type(uint256).max` is treated as unlimited and is never reduced, so a user who approves a spender for the maximum has given that spender permanent control of their shares until they reset it to 0.
7. **Pausing blocks `deposit` only.** `redeem` has no pause check.
8. **The interface declares only the vault's own surface.** `transferOwnership` and `acceptOwnership` come from OpenZeppelin `Ownable2Step` and are not redeclared in `IVault`. Errors that OpenZeppelin already defines (`EnforcedPause`, `OwnableUnauthorizedAccount`, `ERC20InsufficientAllowance`, `ERC20InsufficientBalance`) are inherited, not duplicated.
9. **Errors carry the numbers needed to debug a failure.** `DepositCapExceeded` reports the attempted amount and the room left under the cap (0 if the vault is already at or above it).
10. **`deposit` and `redeem` emit the standard `Deposit` and `Withdraw` events**, so wallets and indexers recognise them.
11. **The deposit cap is a maximum on total assets.** It is never reduced by deposits. If the owner sets it below the current total assets, new deposits revert and existing holders are unaffected: they can still redeem everything.
12. **Ownership cannot be renounced.** `renounceOwnership` is disabled, so the admin controls can never be lost by accident.
13. **A zero receiver is rejected on both paths.** `deposit` to the zero address reverts inside the share token (`ERC20InvalidReceiver`); `redeem` to the zero address reverts with `ZeroAddress`.
14. **The share token copies the asset's decimals**, so shares display in the same units as the asset. The asset must implement `decimals()`.
15. **The first deposit locks 1,000 shares forever** to defend against the inflation attack. The reasoning is in the next section.

## Inflation attack: test and defense

### The attack on the naive vault

The first version of the vault priced the first deposit 1:1 and read the real token balance, with no protection. Here is the attack I proved against it, with a 6-decimal token:

1. The attacker deposits **1 base unit** and gets 1 share.
2. The attacker sends **2,500 USDC** (2,500,000,000 base units) straight to the vault. This changes the real balance but mints no shares, so one share is now worth about 2,500 USDC.
3. A victim deposits **5,000 USDC**. They get `5,000,000,000 × 1 // 2,500,000,001 = 1` share, because the division rounds down.
4. The victim redeems their one share for **3,750 USDC** and lost **1,250 USDC**. The attacker redeems theirs for 3,750,000,001 base units. They spent 2,500,000,001 and made **+1,250 USDC**, exactly the victim's loss.

The textbook version of the attack, with a 10,000 USDC donation, does *not* work against this vault, even before the defense: the victim would get 0 shares, and decision 4 makes that deposit revert, so the victim loses nothing. The attacker's best donation is the smaller one above, where the victim gets exactly 1 share.

This test passed against the vault before the defense was added, with the results above. It is kept, commented out, at the bottom of `test/attack/InflationAttack.t.sol`, because it can no longer pass against the defended vault.

### The defense: lock the first 1,000 shares

On the very first deposit, the vault mints **1,000 shares to `0x…dEaD`**, an address nobody controls, and mints the rest to the receiver. The locked shares count in `totalSupply` but can never be redeemed, so the supply can never fall back to a tiny number. A first deposit of 1,000 base units or fewer reverts with `ZeroShares`, because nothing would be left for the depositor.

**Why this and not something simpler.** Nobody can stop a donation, since a token can always be sent to any address. So the vault must make the donation useless. A minimum size for the first deposit alone is not enough: the attacker deposits the minimum, redeems all but one share, and is back at the starting state of the attack (1 share, 1 base unit). The lock works because those shares can never be redeemed.

**What the tests show** (`test/attack/InflationAttack.t.sol`):

| Test | Result |
|---|---|
| The original attack, `deposit(1)` | Reverts with `ZeroShares(1)`. The attack cannot start. |
| The best adapted attack: deposit 1,001 base units (1 share), donate 2,500 USDC, victim deposits 5,000 USDC | The victim gets 2,001 shares and loses **832,111 base units (0.83 USDC)**. The attacker ends **2,497,502,667 base units (about 2,497 USDC) down**. |

In a Python scan of attacker deposit sizes from 1,001 base units up to 100 million, and donations from 0 to 6,000 USDC, I found no combination where the attacker profits. That scan is not part of the test suite; only the two cases above are tested.

### What this costs

1. **The first depositor pays a small tax.** They receive 1,000 fewer shares than the assets they put in. With a 6-decimal token that is 0.001 USDC. A first deposit of 1,000 base units or fewer is rejected.
2. **Some assets are stuck forever.** The locked shares own a slice of the pool, so the vault never returns to zero. The last real depositor cannot take out 100%, and a small dust amount always stays.
3. **The attack gets expensive, not impossible.** To push a 5,000-token victim down to 1 share, the attacker would have to donate about 2.5 million tokens. A very rich attacker facing a very large deposit is still a risk, and the victim still loses a small rounding amount (0.83 USDC in the test).

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
- renounce ownership

**If the owner key is stolen**, the worst case is that new deposits are stopped, the cap is set to a harmful value (which affects new deposits only), and ownership is passed to the attacker. Existing holders can still redeem.

Tests for these claims: a non-owner cannot call `pause`, `unpause` or `setDepositCap`; the owner cannot redeem a user's shares without an allowance; `redeem` works while paused and while the cap is below total assets; `renounceOwnership` reverts; ownership needs both steps and only the proposed owner can accept.

## Tests

52 tests, all passing: 11 in `VaultMath.t.sol` (10 unit, 1 fuzz), 39 in `Vault.t.sol` (unit, including the fee-on-transfer token tests) and 2 in `InflationAttack.t.sol`. `forge coverage` reports 100% of lines, branches and functions for `src/`.

Coverage only shows that lines ran. The checks I made by deleting a line and seeing whether a test fails:

| Line removed or changed | Does a test fail? |
|---|---|
| `_burn` in `redeem` | Yes |
| The cap revert in `deposit` | Yes |
| The `ZeroShares` revert | Yes |
| `_spendAllowance` in `redeem` | Yes |
| `whenNotPaused` on `deposit` | Yes |
| Pricing shares from `assets` instead of the amount received | Yes (fee-token tests) |
| `_mint(DEAD_ADDRESS, …)` | Yes (11 tests, including the adapted attack) |
| `nonReentrant` on `redeem` | **No.** There is no reentrancy test yet. |
| Cap check using `assets` instead of the amount received | **No.** No test combines a fee token with the cap. |

## Threat model

- **Inflation / donation attack.** Defended by the locked shares; see above.
- **Fee-on-transfer assets.** Shares are priced from the amount actually received. The `Withdraw` event and the return value of `redeem` report the amount sent, not what a fee token delivers to the receiver.
- **Reentrancy.** `deposit` and `redeem` are `nonReentrant`, and `redeem` burns shares before it pays out. There is no test with a malicious token yet.
- **Owner key theft.** Limited to stopping deposits and changing the cap; see Owner powers.
- **Share price manipulation by donation.** Anyone can donate tokens to the vault, which raises the price of every share. This is by design (it is how yield arrives), and it is the reason for the defense above.

## Known limitations

- Not audited.
- The first depositor receives 1,000 fewer shares than the assets deposited, and some dust stays in the vault forever.
- `convertToShares` on an empty vault returns the 1:1 amount, but the first `deposit` mints 1,000 fewer shares. The view and the real deposit disagree for the first deposit only.
- Anyone can donate tokens to push total assets above the cap, which blocks new deposits until the owner raises the cap. It costs the donor the tokens.
- The asset must implement `decimals()` and behave like a standard ERC-20. Rebasing tokens are not supported.
- `Withdraw` and the return value of `redeem` report the amount sent, not the amount a fee-on-transfer token delivers.
- Only `deposit` and `redeem` of the ERC-4626 mutating functions exist. `mint`, `withdraw`, `preview*` and `max*` are not implemented, so the vault is ERC-4626-style, not fully compliant.
- Rounding dust: because conversions round down, a user can get back up to one base unit less than the exact value per operation.
- Share name and symbol are set at deployment.
- Still missing: vault-level fuzz and invariant tests, a reentrancy test, a deploy script and CI.

## License

MIT, see [LICENSE](LICENSE).
