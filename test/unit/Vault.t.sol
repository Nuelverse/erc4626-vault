// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Test} from "forge-std/Test.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MockFeeToken} from "../mocks/MockFeeToken.sol";
import {MockERC20} from "../mocks/MockERC20.sol";
import {Vault, IERC20} from "../../src/Vault.sol";
import {IVault} from "../../src/interfaces/IVault.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract VaultTest is Test {
    MockERC20 mockERC20;
    MockFeeToken feeToken;
    Vault feeVault;
    Vault vault;
    address OWNER;
    address ALICE;
    address BOB;

    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
    event DepositCapUpdated(uint256 oldCap, uint256 newCap);

    function setUp() external {
        OWNER = makeAddr("OWNER");
        mockERC20 = new MockERC20(6, "Mock Token", "MTKN");
        vault = new Vault(mockERC20, OWNER, 100_000e6, "Vault Token", "VTKN");

        ALICE = makeAddr("ALICE");
        BOB = makeAddr("BOB");

        mockERC20.mint(ALICE, 10_000e6);
        mockERC20.mint(BOB, 10_000e6);

        vm.prank(ALICE);
        mockERC20.approve(address(vault), 10_000e6);

        vm.prank(BOB);
        mockERC20.approve(address(vault), 10_000e6);

        feeToken = new MockFeeToken("Fee Token", "FEE");
        feeVault = new Vault(feeToken, OWNER, 100_000e6, "Fee Vault", "FVLT");

        feeToken.mint(ALICE, 10_000e6);
        feeToken.mint(BOB, 10_000e6);

        vm.prank(ALICE);
        feeToken.approve(address(feeVault), 10_000e6);

        vm.prank(BOB);
        feeToken.approve(address(feeVault), 10_000e6);
    }

    function test_constructor_revertsOnZeroAsset() external {
        vm.expectRevert(IVault.InvalidAsset.selector);
        new Vault(IERC20(address(0)), OWNER, 100_000e6, "Vault Token", "VTKN");
    }

    function test_decimals_matchesAsset() external view {
        assertEq(vault.decimals(), 6);
    }

    function test_asset_returnsAssetAddress() external view {
        assertEq(vault.asset(), address(mockERC20));
    }

    function test_totalAssets_includesDonation() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);
        mockERC20.mint(address(vault), 1_000e6);

        assertEq(vault.totalAssets(), 2_000e6);
    }

    function test_convertToShares_afterYield() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);
        mockERC20.mint(address(vault), 1_000e6);

        assertEq(vault.convertToShares(500e6), 250e6);
    }

    function test_convertToAssets_afterYield() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);
        mockERC20.mint(address(vault), 1_000e6);

        assertEq(vault.convertToAssets(400e6), 800e6);
    }

    //// Deposit Tests ////

    function test_deposit_firstDeposit() external {
        vm.expectEmit(true, true, false, true);
        emit Deposit(ALICE, ALICE, 1_000e6, 1_000e6);

        vm.prank(ALICE);
        uint256 shares = vault.deposit(1_000e6, ALICE);

        assertEq(shares, 1_000e6);
        assertEq(mockERC20.balanceOf(address(vault)), 1_000e6);
        assertEq(vault.totalSupply(), 1_000e6);
        assertEq(mockERC20.balanceOf(ALICE), 9_000e6);
        assertEq(vault.depositCap(), 100_000e6);
    }

    function test_deposit_toDifferentReceiver() external {
        vm.prank(ALICE);
        uint256 shares = vault.deposit(5_00e6, BOB);

        assertEq(shares, 5_00e6);
        assertEq(vault.balanceOf(BOB), shares);
        assertEq(vault.balanceOf(ALICE), 0);
        assertEq(mockERC20.balanceOf(ALICE), 9_500e6);
    }

    function test_deposit_afterYield_priceAboveOne() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);
        mockERC20.mint(address(vault), 1_000e6);
        vm.prank(BOB);
        uint256 shares = vault.deposit(5_00e6, BOB);

        assertEq(shares, 250e6);
        assertEq(vault.totalSupply(), 1_250e6);
        assertEq(vault.balanceOf(BOB), 250e6);
    }

    function test_deposit_revertsOnZeroAmount() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);
        vm.expectRevert(abi.encodeWithSelector(IVault.ZeroShares.selector, 0));
        vm.prank(ALICE);
        vault.deposit(0, ALICE);
    }

    function test_deposit_revertsWhenSharesRoundToZero() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);
        mockERC20.mint(address(vault), 1_000e6);

        vm.expectRevert(abi.encodeWithSelector(IVault.ZeroShares.selector, 1));

        vm.prank(BOB);
        vault.deposit(1, BOB);
    }

    function test_deposit_revertsWhenCapExceeded() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);

        vm.prank(OWNER);
        vault.setDepositCap(1_500e6);
        vm.expectRevert(abi.encodeWithSelector(IVault.DepositCapExceeded.selector, 600e6, 500e6));

        vm.prank(BOB);
        vault.deposit(600e6, BOB);
    }

    function test_deposit_exactlyFillsCap() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);

        vm.prank(OWNER);
        vault.setDepositCap(1_500e6);

        vm.prank(BOB);
        vault.deposit(500e6, BOB);

        assertEq(mockERC20.balanceOf(address(vault)), vault.depositCap());
    }

    function test_deposit_revertsWhenPaused() external {
        vm.prank(OWNER);
        vault.pause();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);
    }

    function test_deposit_revertsForZeroReceiver() external {
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        vault.deposit(1_000e6, address(0));
    }

    ////////// Redeem Tests ///////////

    function test_redeem_all() external {
        vm.startPrank(ALICE);
        vault.deposit(1_000e6, ALICE);

        vm.expectEmit(true, true, true, true);
        emit Withdraw(ALICE, ALICE, ALICE, 1_000e6, 1_000e6);
        uint256 assets = vault.redeem(1_000e6, ALICE, ALICE);
        vm.stopPrank();

        assertEq(assets, 1_000e6);
        assertEq(vault.totalSupply(), 0);
        assertEq(mockERC20.balanceOf(address(vault)), 0);
        assertEq(mockERC20.balanceOf(ALICE), 10_000e6);
    }

    function test_redeem_afterYield() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);
        mockERC20.mint(address(vault), 1_000e6);

        vm.prank(ALICE);
        uint256 assets = vault.redeem(400e6, ALICE, ALICE);
        assertEq(assets, 800e6);
        assertEq(mockERC20.balanceOf(ALICE), 9_800e6);
        assertEq(vault.balanceOf(ALICE), 600e6);
    }

    function test_redeem_forOwnerWithAllowance() external {
        vm.startPrank(ALICE);
        vault.deposit(1_000e6, ALICE);
        vault.approve(BOB, 500e6);
        vm.stopPrank();
        mockERC20.mint(address(vault), 1_000e6);

        vm.prank(BOB);
        uint256 assets = vault.redeem(400e6, BOB, ALICE);

        assertEq(assets, 800e6);
        assertEq(vault.allowance(ALICE, BOB), 100e6);
    }

    function test_redeem_revertsWithoutAllowance() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 0, 400e6));

        vm.prank(BOB);
        vault.redeem(400e6, BOB, ALICE);
    }

    function test_redeem_revertsForZeroReceiver() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);

        vm.expectRevert(IVault.ZeroAddress.selector);

        vm.prank(ALICE);
        vault.redeem(400e6, address(0), ALICE);
    }

    function test_redeem_worksWhilePaused() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);

        vm.prank(OWNER);
        vault.pause();

        vm.prank(ALICE);
        uint256 assets = vault.redeem(400e6, ALICE, ALICE);
        assertEq(assets, 400e6);
    }

    function test_redeem_revertsOnZeroShares() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);

        vm.expectRevert(abi.encodeWithSelector(IVault.ZeroAssets.selector, 0));

        vm.prank(ALICE);
        vault.redeem(0, ALICE, ALICE);
    }

    function test_redeem_revertsWhenAllowanceTooSmall() external {
        vm.startPrank(ALICE);
        vault.deposit(1_000e6, ALICE);
        vault.approve(BOB, 100e6);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, BOB, 100e6, 400e6));
        vm.prank(BOB);
        vault.redeem(400e6, BOB, ALICE);
    }

    function test_redeem_maxAllowanceIsNotReduced() external {
        vm.startPrank(ALICE);
        vault.deposit(1_000e6, ALICE);
        vault.approve(BOB, type(uint256).max);
        vm.stopPrank();

        vm.prank(BOB);
        vault.redeem(400e6, BOB, ALICE);

        assertEq(vault.allowance(ALICE, BOB), type(uint256).max);
    }

    function test_redeem_revertsZeroAssetsWhenVaultLostAssets() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);

        // forge std cheatcode that sets a token balance directly
        deal(address(mockERC20), address(vault), 0);

        vm.expectRevert(abi.encodeWithSelector(IVault.ZeroAssets.selector, 1));
        vm.prank(ALICE);
        vault.redeem(1, ALICE, ALICE);
    }

    /////// Cap Tests /////////

    function test_deposit_revertsWhenCapBelowTotalAssets() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);

        vm.prank(OWNER);
        vault.setDepositCap(500e6);

        vm.expectRevert(abi.encodeWithSelector(IVault.DepositCapExceeded.selector, 1, 0));
        vm.prank(BOB);
        vault.deposit(1, BOB);
    }

    function test_redeem_worksWhenCapBelowTotalAssets() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);

        vm.prank(OWNER);
        vault.setDepositCap(500e6);

        vm.prank(ALICE);
        uint256 assets = vault.redeem(1_000e6, ALICE, ALICE);
        assertEq(assets, 1_000e6);
    }

    /////// Admin Controls Test ////////

    function test_pause_revertsForNonOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, BOB));
        vm.prank(BOB);
        vault.pause();
    }

    function test_unpause_revertsForNonOwner() external {
        vm.prank(OWNER);
        vault.pause();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, BOB));
        vm.prank(BOB);
        vault.unpause();
    }

    function test_unpause_allowsDepositsAgain() external {
        vm.startPrank(OWNER);
        vault.pause();
        vault.unpause();
        vm.stopPrank();

        vm.prank(ALICE);
        uint256 shares = vault.deposit(1_000e6, ALICE);
        assertEq(shares, 1_000e6);
    }

    function test_setDepositCap_revertsForNonOwner() external {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, BOB));
        vm.prank(BOB);
        vault.setDepositCap(1);
    }

    function test_setDepositCap_updatesAndEmits() external {
        vm.expectEmit(false, false, false, true);
        emit DepositCapUpdated(100_000e6, 5_000e6);

        vm.prank(OWNER);
        vault.setDepositCap(5_000e6);

        assertEq(vault.depositCap(), 5_000e6);
    }

    function test_renounceOwnership_alwaysReverts() external {
        vm.expectRevert(IVault.OwnershipRenounceDisabled.selector);
        vm.prank(OWNER);
        vault.renounceOwnership();

        assertEq(vault.owner(), OWNER);
    }

    function test_ownership_twoStepTransfer() external {
        vm.prank(OWNER);
        vault.transferOwnership(BOB);

        assertEq(vault.owner(), OWNER);
        assertEq(vault.pendingOwner(), BOB);

        vm.prank(BOB);
        vault.acceptOwnership();

        assertEq(vault.owner(), BOB);
    }

    function test_ownership_onlyPendingOwnerCanAccept() external {
        vm.prank(OWNER);
        vault.transferOwnership(BOB);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ALICE));
        vm.prank(ALICE);
        vault.acceptOwnership();
    }

    function test_owner_cannotRedeemUsersShares() external {
        vm.prank(ALICE);
        vault.deposit(1_000e6, ALICE);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, OWNER, 0, 1_000e6));
        vm.prank(OWNER);
        vault.redeem(1_000e6, OWNER, ALICE);
    }

    //// MockFeeToken Tests /////

    function test_deposit_feeOnTransfer_firstDeposit() external {
        vm.expectEmit(true, true, false, true);
        emit Deposit(ALICE, ALICE, 900e6, 900e6);

        vm.prank(ALICE);
        uint256 shares = feeVault.deposit(1_000e6, ALICE);

        assertEq(shares, 900e6);
        assertEq(feeVault.balanceOf(ALICE), 900e6);
        assertEq(feeToken.balanceOf(address(feeVault)), 900e6);
        assertEq(feeToken.balanceOf(ALICE), 9_000e6);
    }

    function test_deposit_feeOnTransfer_secondDeposit() external {
        vm.prank(ALICE);
        feeVault.deposit(1_000e6, ALICE);

        vm.prank(BOB);
        uint256 bobShares = feeVault.deposit(500e6, BOB);

        assertEq(bobShares, 450e6);
        assertEq(feeToken.balanceOf(address(feeVault)), 1_350e6);
        assertEq(feeVault.totalSupply(), 1_350e6);
    }

    function test_redeem_feeOnTransfer_cannotTakeMoreThanVaultHolds() external {
        vm.startPrank(ALICE);
        feeVault.deposit(1_000e6, ALICE);
        uint256 assets = feeVault.redeem(900e6, ALICE, ALICE);
        vm.stopPrank();

        assertEq(assets, 900e6);
        assertEq(feeToken.balanceOf(address(feeVault)), 0);
        assertEq(feeToken.balanceOf(ALICE), 9_810e6);
        assertEq(feeVault.totalSupply(), 0);
    }
}
