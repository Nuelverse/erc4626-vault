//SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {IVault} from "./interfaces/IVault.sol";
import {VaultMath} from "./libraries/VaultMath.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

/// @title Vault
/// @notice An ERC-4626-style vault: depositors pool one ERC-20 (the asset) and receive shares whose price rises as
/// assets are added to the vault. The vault is itself the ERC-20 share token.
/// @dev Not audited. Share price is `totalAssets / totalSupply` where `totalAssets` is the vault's real token
/// balance, so tokens sent directly to the vault raise the price of every share. Both conversions round down in
/// the vault's favour. The owner can pause deposits, set the deposit cap and transfer ownership (two steps); the
/// owner has no function that moves, freezes or redirects user funds, and `redeem` is never blocked.
contract Vault is IVault, ERC20, ReentrancyGuard, Pausable, Ownable2Step {
    using SafeERC20 for IERC20;

    /// @dev The pooled token. Immutable: it can never be changed, not even by the owner.
    IERC20 immutable i_asset;

    /// @dev Decimals of the share token, copied from the asset at deployment so shares display like the asset.
    uint8 private immutable i_decimals;

    /// @notice The maximum total assets the vault accepts. Affects new deposits only.
    uint256 public depositCap;

    /// @notice Deploy a vault for `asset_`.
    /// @dev Reverts with {InvalidAsset} for the zero address. A zero `owner_` reverts inside `Ownable`. Emits
    /// {DepositCapUpdated} with an old cap of 0. The asset must implement `decimals()`.
    /// @param asset_ The ERC-20 token to pool.
    /// @param owner_ The first owner (can pause deposits, set the cap and transfer ownership).
    /// @param initialDepositCap The starting cap on total assets, in asset base units.
    /// @param tokenName The name of the share token.
    /// @param tokenSymbol The symbol of the share token.
    constructor(
        IERC20 asset_,
        address owner_,
        uint256 initialDepositCap,
        string memory tokenName,
        string memory tokenSymbol
    ) ERC20(tokenName, tokenSymbol) Ownable(owner_) {
        if (address(asset_) == address(0)) {
            revert InvalidAsset();
        }
        i_asset = asset_;
        i_decimals = IERC20Metadata(address(asset_)).decimals();
        depositCap = initialDepositCap;
        emit DepositCapUpdated(0, depositCap);
    }

    /// @inheritdoc IVault
    /// @dev Measures the balance before and after the transfer and prices shares from the amount actually
    /// received. The transfer-in happens before the share maths (a deliberate exception to strict CEI), which is
    /// why the function is `nonReentrant`. Shares are priced from the balance before the deposit.
    function deposit(uint256 assets, address receiver)
        public
        nonReentrant
        whenNotPaused
        returns (uint256 sharesMinted)
    {
        uint256 vaultBalanceBefore = i_asset.balanceOf(address(this));
        i_asset.safeTransferFrom(msg.sender, address(this), assets);
        uint256 vaultBalanceAfter = i_asset.balanceOf(address(this));

        uint256 amountReceived = vaultBalanceAfter - vaultBalanceBefore;

        // deposit cap check
        uint256 capLeft = depositCap > vaultBalanceBefore ? depositCap - vaultBalanceBefore : 0;

        if (amountReceived > capLeft) {
            revert DepositCapExceeded(amountReceived, capLeft);
        }
        sharesMinted = VaultMath.assetsToShares(amountReceived, vaultBalanceBefore, totalSupply());
        if (sharesMinted == 0) {
            revert ZeroShares(amountReceived);
        }
        _mint(receiver, sharesMinted);
        emit Deposit(msg.sender, receiver, amountReceived, sharesMinted);
    }

    /// @notice The decimals of the share token, equal to the asset's decimals.
    /// @return The number of decimals.
    function decimals() public view override returns (uint8) {
        return i_decimals;
    }

    /// @inheritdoc IVault
    /// @dev Reverts with {ZeroAddress} if `receiver` is the zero address. Never paused. The price is computed
    /// before the shares are burned, the burn happens before the payout, and the payout is the last step.
    function redeem(uint256 shares, address receiver, address sharesOwner)
        public
        nonReentrant
        returns (uint256 assetsPaidOut)
    {
        if (receiver == address(0)) {
            revert ZeroAddress();
        }
        if (sharesOwner != msg.sender) {
            _spendAllowance(sharesOwner, msg.sender, shares);
        }
        assetsPaidOut = VaultMath.sharesToAssets(shares, i_asset.balanceOf(address(this)), totalSupply());
        if (assetsPaidOut == 0) {
            revert ZeroAssets(shares);
        }
        _burn(sharesOwner, shares);
        i_asset.safeTransfer(receiver, assetsPaidOut);
        emit Withdraw(msg.sender, receiver, sharesOwner, assetsPaidOut, shares);
    }

    //////// View Functions ////////

    /// @inheritdoc IVault
    function asset() external view returns (address) {
        return address(i_asset);
    }

    /// @inheritdoc IVault
    function totalAssets() public view returns (uint256) {
        return i_asset.balanceOf(address(this));
    }

    /// @inheritdoc IVault
    function convertToShares(uint256 assets) external view returns (uint256) {
        return VaultMath.assetsToShares(assets, totalAssets(), totalSupply());
    }

    /// @inheritdoc IVault
    function convertToAssets(uint256 shares) external view returns (uint256) {
        return VaultMath.sharesToAssets(shares, totalAssets(), totalSupply());
    }

    /////// Admin Functions ////////

    /// @inheritdoc IVault
    function pause() external onlyOwner {
        _pause();
    }

    /// @inheritdoc IVault
    function unpause() external onlyOwner {
        _unpause();
    }

    /// @inheritdoc IVault
    function setDepositCap(uint256 newCap) external onlyOwner {
        uint256 oldDepCap = depositCap;
        depositCap = newCap;
        emit DepositCapUpdated(oldDepCap, depositCap);
    }

    /// @notice Disabled: ownership cannot be renounced, so the admin controls can never be locked forever.
    /// @dev Always reverts with {OwnershipRenounceDisabled}. Use the two-step `transferOwnership` /
    /// `acceptOwnership` instead.
    function renounceOwnership() public view override onlyOwner {
        revert OwnershipRenounceDisabled();
    }
}
