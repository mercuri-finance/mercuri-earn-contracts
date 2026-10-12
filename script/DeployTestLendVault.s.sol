// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/console2.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TestLendVault} from "../src/TestLendVault.sol";
import {EarnDeployBase} from "./EarnDeployBase.sol";

/// @notice Deploys Earn's test vault on Arc testnet from `deployments/manifest-5042002.json`.
/// @dev Refuses every other chain, a zero owner and an asset without code, and checks the deployed vault's wiring
///      before returning. `write-earn-record.py` writes the deployment record from the completed broadcast.
contract DeployTestLendVault is EarnDeployBase {
    /// @notice Deploys the vault named by this chain's manifest.
    /// @return vault The deployed vault.
    function run() external returns (TestLendVault vault) {
        _requireArcTestnet();
        string memory manifest = _manifest();
        address asset = vm.parseJsonAddress(manifest, ".asset");
        address owner = vm.parseJsonAddress(manifest, ".owner");
        if (owner == address(0)) revert ManifestMismatch("owner");
        _requireCode("asset", asset);

        vm.startBroadcast();
        vault = new TestLendVault(
            IERC20(asset), vm.parseJsonString(manifest, ".name"), vm.parseJsonString(manifest, ".symbol"), owner
        );
        vm.stopBroadcast();

        if (vault.asset() != asset) revert DeploymentMismatch("asset");
        if (vault.owner() != owner) revert DeploymentMismatch("owner");
        if (vault.withdrawLimit() != type(uint256).max) revert DeploymentMismatch("withdrawLimit");
        console2.log("TestLendVault", address(vault), "block", block.number);
    }
}
