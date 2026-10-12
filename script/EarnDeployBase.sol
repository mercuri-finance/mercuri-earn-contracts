// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";
import {VmSafe} from "forge-std/Vm.sol";

/// @notice Shared checks for the Earn deployment scripts. Holds no key and never broadcasts by itself.
/// @dev Every input comes from `deployments/manifest-<chainId>.json`, so a deployment is reviewed as a data change.
abstract contract EarnDeployBase is Script {
    uint256 internal constant TESTNET_CHAIN_ID = 5042002;

    error WrongChain(uint256 chainId);
    error NotArcNode(string clientVersion);
    error NoCode(string name, address account);
    error ManifestMismatch(string field);
    error DeploymentMismatch(string what);

    /// @dev Refuses any chain other than Arc testnet: Earn's test vault must never reach mainnet. A local fork keeps
    ///      testnet's chain id.
    function _requireArcTestnet() internal {
        if (block.chainid != TESTNET_CHAIN_ID) revert WrongChain(block.chainid);
        if (vm.isContext(VmSafe.ForgeContext.ScriptBroadcast)) {
            _requireArcOrAnvilNode(vm.rpc("web3_clientVersion", "[]"));
        }
    }

    /// @dev A broadcast must reach an Arc node or a loopback Anvil fork: any other client that reports Arc's chain id
    ///      (a hosted simulator, another dev node) would write broadcast files indistinguishable from a real deploy.
    function _requireArcOrAnvilNode(bytes memory clientVersion) internal pure {
        // The cheatcode returns the version bare; a JSON-quoted one is accepted too.
        uint256 offset = clientVersion.length > 0 && clientVersion[0] == '"' ? 1 : 0;
        if (!_startsWith(clientVersion, offset, bytes("arc/")) && !_startsWith(clientVersion, offset, bytes("anvil/")))
        {
            revert NotArcNode(string(clientVersion));
        }
    }

    function _startsWith(bytes memory haystack, uint256 offset, bytes memory prefix) internal pure returns (bool) {
        if (offset + prefix.length > haystack.length) return false;
        for (uint256 i; i < prefix.length; ++i) {
            if (haystack[offset + i] != prefix[i]) return false;
        }
        return true;
    }

    /// @dev This chain's manifest, `deployments/manifest-<chainId>.json`, checked to name this chain.
    function _manifest() internal view returns (string memory manifest) {
        manifest = vm.readFile(string.concat("deployments/manifest-", vm.toString(block.chainid), ".json"));
        if (vm.parseJsonUint(manifest, ".chainId") != block.chainid) revert ManifestMismatch("chainId");
    }

    function _requireCode(string memory name, address account) internal view {
        if (account.code.length == 0) revert NoCode(name, account);
    }
}
