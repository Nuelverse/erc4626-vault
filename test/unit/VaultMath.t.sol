// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {VaultMath} from "../../src/libraries/VaultMath.sol";

contract VaultMathTest is Test {
    function test_assetsToShares_isOneToOneWhenSupplyIsZero() external pure {
        uint256 assets = 100;
        uint256 totalAssets = 0;
        uint256 totalSupply = 0;

        uint256 shares = VaultMath.assetsToShares(assets, totalAssets, totalSupply);
        assertEq(shares, 100);
    }

    function test_assetsToShares_exactDivision() external pure {
        uint256 assets = 100;
        uint256 totalAssets = 200;
        uint256 totalSupply = 50;

        uint256 shares = VaultMath.assetsToShares(assets, totalAssets, totalSupply);
        assertEq(shares, 25);
    }

    function test_assetsToShares_roundsDownWithRemainder() external pure {
        uint256 assets = 1;
        uint256 totalAssets = 3;
        uint256 totalSupply = 10;

        uint256 shares = VaultMath.assetsToShares(assets, totalAssets, totalSupply);
        assertEq(shares, 3);
    }

    function test_assetsToShares_returnsZeroWhenAssetsTooSmall() external pure {
        uint256 assets = 3;
        uint256 totalAssets = 13;
        uint256 totalSupply = 4;

        uint256 shares = VaultMath.assetsToShares(assets, totalAssets, totalSupply);
        assertEq(shares, 0);
    }

    function test_assetsToShares_returnsZeroForZeroAssets() external pure {
        uint256 assets = 0;
        uint256 totalAssets = 200;
        uint256 totalSupply = 50;

        uint256 shares = VaultMath.assetsToShares(assets, totalAssets, totalSupply);
        assertEq(shares, 0);
    }

    function test_sharesToAssets_exactDivision() external pure {
        uint256 shares = 25;
        uint256 totalAssets = 200;
        uint256 totalSupply = 50;

        uint256 assets = VaultMath.sharesToAssets(shares, totalAssets, totalSupply);
        assertEq(assets, 100);
    }

    function test_sharesToAssets_roundsDownWithRemainder() external pure {
        uint256 shares = 2;
        uint256 totalAssets = 10;
        uint256 totalSupply = 3;

        uint256 assets = VaultMath.sharesToAssets(shares, totalAssets, totalSupply);
        assertEq(assets, 6);
    }

    function test_sharesToAssets_returnsZeroWhenSharesTooSmall() external pure {
        uint256 shares = 3;
        uint256 totalAssets = 4;
        uint256 totalSupply = 13;

        uint256 assets = VaultMath.sharesToAssets(shares, totalAssets, totalSupply);
        assertEq(assets, 0);
    }

    function test_assetsToShares_whenTotalAssetsIsZero() external pure {
        uint256 assets = 100;
        uint256 totalAssets = 0;
        uint256 totalSupply = 50;

        uint256 shares = VaultMath.assetsToShares(assets, totalAssets, totalSupply);
        assertEq(shares, 0);
    }

    function test_sharesToAssets_whenSupplyIsZero() external pure {
        uint256 shares = 100;
        uint256 totalAssets = 500;
        uint256 totalSupply = 0;

        uint256 assets = VaultMath.sharesToAssets(shares, totalAssets, totalSupply);
        assertEq(assets, 0);
    }

    function testFuzz_roundTrip_neverReturnsMoreThanDeposited(uint256 assets, uint256 totalAssets, uint256 totalSupply)
        external
        pure
    {
        assets = bound(assets, 0, 50000e18);
        totalAssets = bound(totalAssets, 0, 100000e18);
        totalSupply = bound(totalSupply, 0, 25000e18);

        uint256 shares = VaultMath.assetsToShares(assets, totalAssets, totalSupply);
        uint256 a = VaultMath.sharesToAssets(shares, totalAssets, totalSupply);

        assertLe(a, assets);
    }
}
