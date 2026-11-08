// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockFeeToken is ERC20 {
    uint8 immutable i_decimals;
    uint256 public constant PERCENTAGE = 10; // 10%

    constructor(string memory tokenName, string memory tokenSymbol) ERC20(tokenName, tokenSymbol) {
        i_decimals = 6;
    }

    function decimals() public view override returns (uint8) {
        return i_decimals;
    }

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0)) {
            uint256 fee = (value * PERCENTAGE) / 100;
            super._update(from, to, value - fee);
            super._update(from, address(0), fee);
            return;
        }
        super._update(from, to, value);
    }
}
