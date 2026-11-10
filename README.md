# erc4626-vault

[![CI](https://github.com/Nuelverse/erc4626-vault/actions/workflows/test.yml/badge.svg)](https://github.com/Nuelverse/erc4626-vault/actions/workflows/test.yml)

A multi-file, ERC-4626-style token vault built with Foundry. Depositors pool one ERC-20 (the asset) and receive shares; the share price rises when yield is sent to the vault.

> **Not audited.** This is a learning project.

## Layout

```
src/
  interfaces/IVault.sol     public surface: signatures, events, custom errors
  libraries/VaultMath.sol   pure share/asset conversions with explicit rounding
  Vault.sol                 state, deposit, redeem, admin controls
test/
  unit/                     VaultMath and Vault unit tests, reentrancy tests
  fuzz/                     fuzz tests on the real vault
  invariant/                invariant tests with a handler contract
  attack/                   the inflation-attack tests
  mocks/                    MockERC20, MockFeeToken (10% fee on every transfer), MockReentrantToken (calls back into the vault)
script/
  DeployVault.s.sol         deploys the vault
  HelperConfig.s.sol        picks the asset for the chain (test USDC on Sepolia, a mock on a local Anvil chain)
```

## How to run

```shell
git clone --recurse-submodules https://github.com/Nuelverse/erc4626-vault.git
cd erc4626-vault
forge build
forge test
forge fmt --check
```

## Deployed on Sepolia

|                    |                                                                                                                                                                     |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Vault              | [`0x26Af3252E6619Fb6730524dc8DbCEe42c5DCa75F`](https://sepolia.etherscan.io/address/0x26af3252e6619fb6730524dc8dbcee42c5dca75f#code) (source verified on Etherscan) |
| Asset              | Circle's test USDC, `0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238` (6 decimals)                                                                                       |
| Deploy transaction | `0xfa0924aeec2175693d5b1507f925075479d73949e3551721251ba2e8c4fc6853`                                                                                                |
| Owner              | `0x3a7471C5B78A5ba3958Be906bacb40492a5d2200` (a single key, the same one that deployed it)                                                                          |
| Deposit cap        | 100,000 USDC                                                                                                                                                        |

## Design

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

The textbook version of the attack, with a 10,000 USDC donation, does _not_ work against this vault, even before the defense: the victim would get 0 shares, and decision 4 makes that deposit revert, so the victim loses nothing. The attacker's best donation is the smaller one above, where the victim gets exactly 1 share.

This test passed against the vault before the defense was added, with the results above. It is kept, commented out, at the bottom of `test/attack/InflationAttack.t.sol`, because it can no longer pass against the defended vault.

### The defense: lock the first 1,000 shares

On the very first deposit, the vault mints **1,000 shares to `0x…dEaD`**, an address nobody controls, and mints the rest to the receiver. The locked shares count in `totalSupply` but can never be redeemed, so the supply can never fall back to a tiny number. A first deposit of 1,000 base units or fewer reverts with `ZeroShares`, because nothing would be left for the depositor.

**Why this and not something simpler.** Nobody can stop a donation, since a token can always be sent to any address. So the vault must make the donation useless. A minimum size for the first deposit alone is not enough: the attacker deposits the minimum, redeems all but one share, and is back at the starting state of the attack (1 share, 1 base unit). The lock works because those shares can never be redeemed.

**What the tests show** (`test/attack/InflationAttack.t.sol`):

| Test                                                                                                       | Result                                                                                                                                             |
| ---------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| The original attack, `deposit(1)`                                                                          | Reverts with `ZeroShares(1)`. The attack cannot start.                                                                                             |
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

`forge test` reports **59 passing tests**. Counting the test functions in the files gives 60: the difference is the invariant suite, which holds two invariants but is tallied as one result.

## Threat model

- **Fee-on-transfer assets.** Shares are priced from the amount actually received. The `Withdraw` event and the return value of `redeem` report the amount sent, not what a fee token delivers to the receiver.
- **Reentrancy.** `deposit` and `redeem` are `nonReentrant`, and `redeem` burns shares before it pays out. A malicious token that calls back during a deposit or a redeem is blocked in both cases (`Reentrancy.t.sol`).
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

## License

MIT, see [LICENSE](LICENSE).
