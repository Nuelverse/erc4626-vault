// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Vault} from "../../src/Vault.sol";

contract VaultFuzzTest is Test {
    MockERC20 token;
    Vault vault;
    address OWNER;
    address ALICE;
    address BOB;

    function setUp() external {
        OWNER = makeAddr("OWNER");
        ALICE = makeAddr("ALICE");
        BOB = makeAddr("BOB");
        token = new MockERC20(6, "Mock Token", "MTKN");
        vault = new Vault(token, OWNER, type(uint256).max, "Vault Token", "VTKN");

        token.mint(ALICE, 1e30);
        token.mint(BOB, 1e30);
        vm.prank(ALICE);
        token.approve(address(vault), type(uint256).max);
        vm.prank(BOB);
        token.approve(address(vault), type(uint256).max);

        // Alice makes the first deposit, so every fuzzed run starts from an existing vault
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);
    }

    function testFuzz_depositThenRedeem_neverReturnsMoreThanDeposited(uint256 donation, uint256 amount) external {
        donation = bound(donation, 0, 1e15);
        amount = bound(amount, 1, 1e15);
        token.mint(address(vault), donation);

        vm.prank(BOB);
        try vault.deposit(amount, BOB) returns (uint256 shares) {
            vm.prank(BOB);
            uint256 assetsBack = vault.redeem(shares, BOB, BOB);
            assertLe(assetsBack, amount);
        } catch {
            // a deposit that would mint zero shares reverts; nothing to check
        }
    }

    function testFuzz_deposit_sharePriceNeverDecreases(uint256 donation, uint256 amount) external {
        donation = bound(donation, 0, 1e15);
        amount = bound(amount, 1, 1e15);
        token.mint(address(vault), donation);

        uint256 assetsBefore = vault.totalAssets();
        uint256 supplyBefore = vault.totalSupply();

        vm.prank(BOB);
        try vault.deposit(amount, BOB) {
            // price = assets / supply, compared by cross-multiplying to avoid dividing
            assertGe(vault.totalAssets() * supplyBefore, assetsBefore * vault.totalSupply());
        } catch {}
    }

    function testFuzz_redeem_sharePriceNeverDecreases(uint256 donation, uint256 shares) external {
        donation = bound(donation, 0, 1e15);
        shares = bound(shares, 1, vault.balanceOf(ALICE));
        token.mint(address(vault), donation);

        uint256 assetsBefore = vault.totalAssets();
        uint256 supplyBefore = vault.totalSupply();

        vm.prank(ALICE);
        try vault.redeem(shares, ALICE, ALICE) {
            assertGe(vault.totalAssets() * supplyBefore, assetsBefore * vault.totalSupply());
        } catch {}
    }
}
