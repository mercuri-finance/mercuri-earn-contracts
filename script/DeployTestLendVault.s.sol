// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {TestLendVault} from "../src/TestLendVault.sol";
import {EarnDeployBase} from "./EarnDeployBase.sol";

/// @notice Deploys Earn's test vault on Arc testnet from `deployments/manifest-5042002.json`.
/// @dev Refuses every other chain, a zero owner and any asset but Arc's six-decimal USDC, checks the deployed vault's
///      wiring, and deposits the manifest's `seedAssets` for the owner in the same broadcast, so no donation can land
///      on an empty vault and set its share scale. The broadcaster must hold the seed. `write-earn-record.py` writes
///      the deployment record from the completed broadcast.
contract DeployTestLendVault is EarnDeployBase {
    /// @notice Deploys the vault named by this chain's manifest.
    /// @return vault The deployed vault.
    function run() external returns (TestLendVault vault) {
        _requireArcTestnet();
        return _deploy(_readManifest(_manifestPath()));
    }

    /// @dev The deployment from a manifest already read and checked for this chain.
    function _deploy(string memory manifest) internal returns (TestLendVault vault) {
        address asset = vm.parseJsonAddress(manifest, ".asset");
        address owner = vm.parseJsonAddress(manifest, ".owner");
        uint256 seed = vm.parseJsonUint(manifest, ".seedAssets");
        if (asset != USDC) revert ManifestMismatch("asset");
        _requireCode("asset", asset);
        if (IERC20Metadata(asset).decimals() != USDC_DECIMALS) revert ManifestMismatch("decimals");
        if (owner == address(0)) revert ManifestMismatch("owner");
        if (seed == 0) revert ManifestMismatch("seedAssets");

        vm.startBroadcast();
        vault = new TestLendVault(
            IERC20(asset), vm.parseJsonString(manifest, ".name"), vm.parseJsonString(manifest, ".symbol"), owner
        );
        IERC20(asset).approve(address(vault), seed);
        vault.deposit(seed, owner);
        vm.stopBroadcast();

        if (vault.asset() != asset) revert DeploymentMismatch("asset");
        if (vault.owner() != owner) revert DeploymentMismatch("owner");
        if (vault.withdrawLimit() != type(uint256).max) revert DeploymentMismatch("withdrawLimit");
        if (vault.totalAssets() != seed || vault.balanceOf(owner) == 0) revert DeploymentMismatch("seed");
        console2.log("TestLendVault", address(vault), "block", block.number);
    }
}
