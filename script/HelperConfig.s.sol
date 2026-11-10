// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MockERC20} from "../test/mocks/MockERC20.sol";

/// @notice Picks the asset to pool for the chain the script runs on.
contract HelperConfig is Script {
    error HelperConfig__UnsupportedChain(uint256 chainId);

    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant ANVIL_CHAIN_ID = 31337;

    /// @dev Circle's test USDC on Sepolia (6 decimals). Check it against Circle's docs before relying on it.
    address public constant SEPOLIA_USDC = 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238;

    function getAsset() external returns (IERC20) {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            return IERC20(SEPOLIA_USDC);
        }
        if (block.chainid == ANVIL_CHAIN_ID) {
            vm.startBroadcast();
            MockERC20 mock = new MockERC20(6, "Mock USDC", "mUSDC");
            vm.stopBroadcast();
            return IERC20(address(mock));
        }
        revert HelperConfig__UnsupportedChain(block.chainid);
    }
}
