// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {MockReentrantToken} from "../mocks/MockReentrantToken.sol";
import {Vault} from "../../src/Vault.sol";

contract ReentrancyTest is Test {
    MockReentrantToken token;
    Vault vault;
    address OWNER;
    address ATTACKER;
    address BYSTANDER;

    function setUp() external {
        OWNER = makeAddr("OWNER");
        ATTACKER = makeAddr("ATTACKER");
        BYSTANDER = makeAddr("BYSTANDER");
        token = new MockReentrantToken("Evil Token", "EVIL");
        vault = new Vault(token, OWNER, 100_000e6, "Vault Token", "VTKN");

        token.mint(ATTACKER, 10_000e6);
        token.mint(BYSTANDER, 10_000e6);

        vm.prank(ATTACKER);
        token.approve(address(vault), 10_000e6);
        vm.prank(BYSTANDER);
        token.approve(address(vault), 10_000e6);

        // the bystander makes the first deposit, so the price is 1:1 and the vault holds 1,000e6
        vm.prank(BYSTANDER);
        vault.deposit(1_000e6, BYSTANDER);
    }

    function test_redeem_blocksReentrantRedeem() external {
        vm.startPrank(ATTACKER);
        vault.deposit(1_000e6, ATTACKER);
        vault.approve(address(token), 500e6);
        vm.stopPrank();

        token.armRedeemReentry(vault, ATTACKER, 500e6);

        vm.prank(ATTACKER);
        uint256 assets = vault.redeem(500e6, ATTACKER, ATTACKER);

        assertTrue(token.reentryAttempted());
        assertFalse(token.reentrySucceeded());
        assertEq(assets, 500e6);
        assertEq(token.balanceOf(ATTACKER), 9_500e6);
        assertEq(token.balanceOf(address(vault)), 1_500e6);
    }

    function test_deposit_blocksReentrantDeposit() external {
        token.armDepositReentry(vault);

        vm.prank(ATTACKER);
        uint256 shares = vault.deposit(500e6, ATTACKER);

        assertTrue(token.reentryAttempted());
        assertFalse(token.reentrySucceeded());
        assertEq(shares, 500e6);
        assertEq(vault.totalSupply(), 1_500e6);
    }
}
