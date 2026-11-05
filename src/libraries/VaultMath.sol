// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @title VaultMath
/// @notice Pure share/asset conversions for the vault. Both directions round down, in the vault's favour.
/// @dev Stateless. It only returns numbers; the vault decides whether a result of 0 is acceptable and reverts
/// with `ZeroShares` or `ZeroAssets`. Division by zero never panics: the undefined cases return 0.
library VaultMath {
    using Math for uint256;

    /// @notice Shares minted for `assets`, rounded down.
    /// @dev If no shares exist, the first deposit is priced 1:1. If shares exist but the vault holds no assets,
    /// the shares cannot be priced and 0 is returned so a deposit reverts instead of diluting existing holders.
    /// @param assets The amount of assets being deposited.
    /// @param totalAssets The vault's current total assets.
    /// @param totalSupply The current total supply of shares.
    /// @return shares The amount of shares to mint.
    function assetsToShares(uint256 assets, uint256 totalAssets, uint256 totalSupply)
        internal
        pure
        returns (uint256 shares)
    {
        if (totalSupply > 0 && totalAssets == 0) {
            shares = 0;
        } else if (totalSupply == 0) {
            shares = assets;
        } else {
            shares = assets.mulDiv(totalSupply, totalAssets, Math.Rounding.Floor);
        }
    }

    /// @notice Assets paid for redeeming `shares`, rounded down.
    /// @dev Returns 0 when no shares exist, since there is nothing to redeem.
    /// @param shares The amount of shares being redeemed.
    /// @param totalAssets The vault's current total assets.
    /// @param totalSupply The current total supply of shares.
    /// @return assets The amount of assets to pay out.
    function sharesToAssets(uint256 shares, uint256 totalAssets, uint256 totalSupply)
        internal
        pure
        returns (uint256 assets)
    {
        if (totalSupply == 0) {
            assets = 0;
        } else {
            assets = shares.mulDiv(totalAssets, totalSupply, Math.Rounding.Floor);
        }
    }
}
