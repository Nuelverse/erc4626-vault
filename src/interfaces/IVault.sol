// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

/// @title IVault
/// @notice Public interface of an ERC-4626-style vault: users deposit one ERC-20 (the asset) and receive shares,
/// and redeem shares for the asset at the current share price.
/// @dev Only `deposit` and `redeem` are implemented from the EIP-4626 mutating functions; `mint`, `withdraw`,
/// `preview*` and `max*` are not part of v1. Ownership functions (`transferOwnership`, `acceptOwnership`)
/// come from OpenZeppelin `Ownable2Step` and are intentionally not declared here. Not audited.
interface IVault {
    // ---------------------------------------------------------------------
    // Errors
    // ---------------------------------------------------------------------

    /// @notice A deposit would mint zero shares, so it is rejected instead of taking the caller's assets for nothing.
    /// @param assets The amount of assets the caller tried to deposit.
    error ZeroShares(uint256 assets);

    /// @notice A redeem would pay out zero assets, so it is rejected instead of burning shares for nothing.
    /// @param shares The amount of shares the caller tried to redeem.
    error ZeroAssets(uint256 shares);

    /// @notice A deposit would push the vault's total assets above the deposit cap.
    /// @param assets The amount of assets the caller tried to deposit.
    /// @param available The room left under the cap; 0 if total assets is already at or above the cap.
    error DepositCapExceeded(uint256 assets, uint256 available);

    /// @notice The asset address given at construction is not valid (the zero address).
    error InvalidAsset();

    /// @notice Thrown when the address passed is a zero address
    error ZeroAddress();

    /// @notice Thrown when ownership is trying to be renounced
    error OwnershipRenounceDisabled();

    // ---------------------------------------------------------------------
    // Events
    // ---------------------------------------------------------------------

    /// @notice Emitted when assets are deposited and shares are minted.
    /// @param sender The address that paid the assets.
    /// @param owner The address that received the shares.
    /// @param assets The amount of assets the vault received.
    /// @param shares The amount of shares minted.
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);

    /// @notice Emitted when shares are redeemed and assets are paid out.
    /// @param sender The address that called `redeem` (the share owner, or a spender with allowance).
    /// @param receiver The address that received the assets.
    /// @param owner The address whose shares were burned.
    /// @param assets The amount of assets paid out.
    /// @param shares The amount of shares burned.
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );

    /// @notice Emitted when the owner changes the deposit cap.
    /// @param oldCap The previous cap, in asset base units.
    /// @param newCap The new cap, in asset base units.
    event DepositCapUpdated(uint256 oldCap, uint256 newCap);

    // ---------------------------------------------------------------------
    // User actions
    // ---------------------------------------------------------------------

    /// @notice Deposit assets and mint shares to `receiver`.
    /// @dev The caller pays. Shares are computed from the amount the vault actually received, not from `assets`,
    /// and rounded down. Reverts if the vault is paused, the cap would be exceeded, or zero shares would be minted.
    /// @param assets The amount of assets to deposit, in asset base units.
    /// @param receiver The address that receives the shares.
    /// @return sharesMinted The amount of shares minted to `receiver`.
    function deposit(uint256 assets, address receiver) external returns (uint256 sharesMinted);

    /// @notice Burn `shares` from `sharesOwner` and send the corresponding assets to `receiver`.
    /// @dev Works while the vault is paused. If the caller is not `sharesOwner`, the caller's share allowance is
    /// spent; an allowance of `type(uint256).max` is treated as unlimited and is not reduced. Assets are rounded
    /// down. Reverts if zero assets would be paid out.
    /// @param shares The amount of shares to burn.
    /// @param receiver The address that receives the assets.
    /// @param sharesOwner The address whose shares are burned.
    /// @return assetsPaidOut The amount of assets sent to `receiver`.
    function redeem(uint256 shares, address receiver, address sharesOwner) external returns (uint256 assetsPaidOut);

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    /// @notice The ERC-20 token pooled by the vault.
    /// @return The address of the asset token.
    function asset() external view returns (address);

    /// @notice The vault's real balance of the asset, including any tokens sent to it directly.
    /// @return The total assets held, in asset base units.
    function totalAssets() external view returns (uint256);

    /// @notice How many shares `assets` would buy at the current share price, rounded down.
    /// @param assets The amount of assets, in asset base units.
    /// @return The equivalent amount of shares.
    function convertToShares(uint256 assets) external view returns (uint256);

    /// @notice How many assets `shares` would redeem for at the current share price, rounded down.
    /// @param shares The amount of shares.
    /// @return The equivalent amount of assets, in asset base units.
    function convertToAssets(uint256 shares) external view returns (uint256);

    // ---------------------------------------------------------------------
    // Owner controls
    // ---------------------------------------------------------------------

    /// @notice Block new deposits. Redemptions are never blocked.
    /// @dev Owner only.
    function pause() external;

    /// @notice Allow deposits again.
    /// @dev Owner only.
    function unpause() external;

    /// @notice Set the maximum total assets the vault accepts.
    /// @dev Owner only. Affects new deposits only; it never moves or locks existing funds. Emits
    /// {DepositCapUpdated}.
    /// @param newCap The new cap, in asset base units.
    function setDepositCap(uint256 newCap) external;
}
