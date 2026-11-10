// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

import {Script} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vault} from "../src/Vault.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

/// @notice Deploys the vault. Set VAULT_OWNER to the address that will own it.
contract DeployVault is Script {
    uint256 public constant INITIAL_DEPOSIT_CAP = 100_000e6;

    function run() external returns (Vault vault) {
        address owner = vm.envAddress("VAULT_OWNER");
        IERC20 asset = new HelperConfig().getAsset();

        vm.startBroadcast();
        vault = new Vault(asset, owner, INITIAL_DEPOSIT_CAP, "Vault Share", "vSHARE");
        vm.stopBroadcast();
    }
}
