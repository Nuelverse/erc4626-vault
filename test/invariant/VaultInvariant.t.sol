// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Vault} from "../../src/Vault.sol";

/// @dev Random actors deposit, redeem and donate. The invariant test then checks the vault's books.
contract VaultHandler is Test {
    MockERC20 public token;
    Vault public vault;
    address[] public actors;

    constructor(MockERC20 token_, Vault vault_) {
        token = token_;
        vault = vault_;
        for (uint256 i = 0; i < 3; i++) {
            address actor = makeAddr(string(abi.encodePacked("actor", i)));
            actors.push(actor);
            token.mint(actor, 1e15);
            vm.prank(actor);
            token.approve(address(vault), type(uint256).max);
        }
    }

    function actorCount() external view returns (uint256) {
        return actors.length;
    }

    function deposit(uint256 actorSeed, uint256 amount) external {
        address actor = actors[actorSeed % actors.length];
        amount = bound(amount, 1, token.balanceOf(actor));
        vm.prank(actor);
        try vault.deposit(amount, actor) {} catch {}
    }

    function redeem(uint256 actorSeed, uint256 shares) external {
        address actor = actors[actorSeed % actors.length];
        uint256 balance = vault.balanceOf(actor);
        if (balance == 0) return;
        shares = bound(shares, 1, balance);
        vm.prank(actor);
        try vault.redeem(shares, actor, actor) {} catch {}
    }

    function donate(uint256 amount) external {
        token.mint(address(vault), bound(amount, 0, 1e12));
    }
}

contract VaultInvariantTest is Test {
    MockERC20 token;
    Vault vault;
    VaultHandler handler;

    function setUp() external {
        token = new MockERC20(6, "Mock Token", "MTKN");
        vault = new Vault(token, makeAddr("OWNER"), type(uint256).max, "Vault Token", "VTKN");
        handler = new VaultHandler(token, vault);
        targetContract(address(handler));
    }

    /// @dev Everything all holders could redeem right now, including the locked shares, is at most what the vault holds.
    function invariant_totalRedeemableNeverExceedsTotalAssets() external view {
        uint256 redeemable = vault.convertToAssets(vault.balanceOf(address(0xdead)));
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            redeemable += vault.convertToAssets(vault.balanceOf(handler.actors(i)));
        }
        assertLe(redeemable, vault.totalAssets());
    }

    /// @dev Every share is accounted for: the supply is the sum of all holders' balances.
    function invariant_supplyEqualsSumOfBalances() external view {
        uint256 sum = vault.balanceOf(address(0xdead));
        for (uint256 i = 0; i < handler.actorCount(); i++) {
            sum += vault.balanceOf(handler.actors(i));
        }
        assertEq(sum, vault.totalSupply());
    }
}
