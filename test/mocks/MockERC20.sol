// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
    uint8 immutable i_decimals;

    constructor(uint8 decimals_, string memory tokenName, string memory tokenSymbol) ERC20(tokenName, tokenSymbol) {
        i_decimals = decimals_;
    }

    function decimals() public view override returns (uint8) {
        return i_decimals;
    }

    // test-only
    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}
