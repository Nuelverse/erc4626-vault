// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Vault} from "../../src/Vault.sol";

contract MockReentrantToken is ERC20 {
    Vault private s_target;
    address private s_shareOwner;
    uint256 private s_reenterShares;
    bool private s_armedRedeem;
    bool private s_armedDeposit;

    bool public reentryAttempted;
    bool public reentrySucceeded;

    constructor(string memory tokenName, string memory tokenSymbol) ERC20(tokenName, tokenSymbol) {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function armRedeemReentry(Vault target, address shareOwner, uint256 shares) external {
        s_target = target;
        s_shareOwner = shareOwner;
        s_reenterShares = shares;
        s_armedRedeem = true;
    }

    function armDepositReentry(Vault target) external {
        s_target = target;
        _mint(address(this), 10);
        _approve(address(this), address(target), type(uint256).max);
        s_armedDeposit = true;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        if (s_armedRedeem && msg.sender == address(s_target)) {
            s_armedRedeem = false;
            reentryAttempted = true;
            try s_target.redeem(s_reenterShares, s_shareOwner, s_shareOwner) {
                reentrySucceeded = true;
            } catch {}
        }
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        if (s_armedDeposit && msg.sender == address(s_target)) {
            s_armedDeposit = false;
            reentryAttempted = true;
            try s_target.deposit(1, address(this)) {
                reentrySucceeded = true;
            } catch {}
        }
        return super.transferFrom(from, to, amount);
    }
}
