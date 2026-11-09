// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Vault} from "../../src/Vault.sol";
import {IVault} from "../../src/interfaces/IVault.sol";

contract InflationAttack is Test {
    MockERC20 mockERC20;
    Vault vault;
    address OWNER;
    address ATTACKER;
    address VICTIM;

    function setUp() external {
        OWNER = makeAddr("OWNER");
        mockERC20 = new MockERC20(6, "Mock Token", "MTKN");
        vault = new Vault(mockERC20, OWNER, 100_000e6, "Vault Token", "VTKN");

        ATTACKER = makeAddr("ATTACKER");
        VICTIM = makeAddr("VICTIM");

        mockERC20.mint(ATTACKER, 10_000e6);
        mockERC20.mint(VICTIM, 10_000e6);

        vm.prank(ATTACKER);
        mockERC20.approve(address(vault), 10_000e6);

        vm.prank(VICTIM);
        mockERC20.approve(address(vault), 10_000e6);
    }

    function test_inflationAttack_defendedVault_originalAttackReverts() external {
        vm.expectRevert(abi.encodeWithSelector(IVault.ZeroShares.selector, 1));
        vm.startPrank(ATTACKER);
        vault.deposit(1, ATTACKER);
    }

    function test_inflationAttack_defendedVault_adaptedAttackLoses() external {
        uint256 attackerBalanceBefore = mockERC20.balanceOf(ATTACKER);

        vm.startPrank(ATTACKER);
        vault.deposit(1_001, ATTACKER);
        mockERC20.transfer(address(vault), 2_500e6);
        vm.stopPrank();

        assertEq(vault.balanceOf(ATTACKER), 1);
        assertEq(vault.totalSupply(), 1_001);
        assertEq(mockERC20.balanceOf(address(vault)), 2_500_001_001);

        vm.prank(VICTIM);
        uint256 victimShares = vault.deposit(5_000e6, VICTIM);
        assertEq(victimShares, 2_001);

        vm.prank(VICTIM);
        uint256 victimReceived = vault.redeem(victimShares, VICTIM, VICTIM);

        vm.prank(ATTACKER);
        vault.redeem(1, ATTACKER, ATTACKER);

        uint256 victimLoss = 5_000e6 - victimReceived;
        uint256 attackerBalanceAfter = mockERC20.balanceOf(ATTACKER);

        assertEq(victimLoss, 832_111);
        assertLt(victimLoss, 1e6);
        assertLt(attackerBalanceAfter, attackerBalanceBefore);
        assertEq(attackerBalanceBefore - attackerBalanceAfter, 2_497_502_667);
    }

    // function test_inflationAttack_naiveVault_attackerProfits() external {
    //     uint256 attackerBalanceBefore = mockERC20.balanceOf(ATTACKER);
    //     vm.startPrank(ATTACKER);
    //     vault.deposit(1, ATTACKER);
    //     assertEq(vault.balanceOf(ATTACKER), 1);

    //     mockERC20.transfer(address(vault), 2_500e6);
    //     vm.stopPrank();

    //     assertEq(mockERC20.balanceOf(address(vault)), 2_500_000_001);
    //     assertEq(vault.totalSupply(), 1);

    //     vm.prank(VICTIM);
    //     vault.deposit(5_000e6, VICTIM);

    //     assertEq(vault.balanceOf(VICTIM), 1);
    //     assertEq(vault.totalSupply(), 2);

    //     vm.prank(VICTIM);
    //     uint256 victimReceived = vault.redeem(1, VICTIM, VICTIM);
    //     assertEq(victimReceived, 3_750e6);

    //     vm.prank(ATTACKER);
    //     uint256 attackerReceived = vault.redeem(1, ATTACKER, ATTACKER);
    //     assertEq(attackerReceived, 3_750_000_001);

    //     uint256 attackerBalanceAfter = mockERC20.balanceOf(ATTACKER);
    //     uint256 attackerProfit = attackerBalanceAfter - attackerBalanceBefore;
    //     uint256 victimLoss = 5_000e6 - victimReceived;

    //     assertEq(victimLoss, 1250e6);
    //     assertGt(attackerBalanceAfter, attackerBalanceBefore);
    //     console2.log("Attacker Profit", attackerProfit);
    //     console2.log("Victim Loss", victimLoss);
    // }
}
