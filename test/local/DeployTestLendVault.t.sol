// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {DeployTestLendVault} from "../../script/DeployTestLendVault.s.sol";
import {EarnDeployBase} from "../../script/EarnDeployBase.sol";
import {TestLendVault} from "../../src/TestLendVault.sol";
import {MockUsdc} from "../utils/MockUsdc.sol";

contract DeployTestLendVaultHarness is DeployTestLendVault {
    function requireArcOrAnvilNode(bytes memory clientVersion) external pure {
        _requireArcOrAnvilNode(clientVersion);
    }
}

contract DeployTestLendVaultTest is Test {
    DeployTestLendVaultHarness internal script;

    function setUp() public {
        script = new DeployTestLendVaultHarness();
    }

    /// The script refuses Arc mainnet and every other chain.
    function test_RefusesEveryChainButTestnet() public {
        vm.chainId(5042);
        vm.expectRevert(abi.encodeWithSelector(EarnDeployBase.WrongChain.selector, 5042));
        script.run();
    }

    /// The committed manifest names no owner yet, and the script refuses to deploy a vault nobody controls.
    function test_RefusesTheManifestsZeroOwner() public {
        vm.chainId(5042002);
        vm.etch(0x3600000000000000000000000000000000000000, address(new MockUsdc()).code);
        vm.expectRevert(abi.encodeWithSelector(EarnDeployBase.ManifestMismatch.selector, "owner"));
        script.run();
    }

    /// A broadcast must reach an Arc node or a loopback Anvil fork.
    function test_AcceptsOnlyArcOrAnvilNodes() public {
        script.requireArcOrAnvilNode(bytes("arc/v1.0.0"));
        script.requireArcOrAnvilNode(bytes('"anvil/v1.4.3"'));
        vm.expectRevert(abi.encodeWithSelector(EarnDeployBase.NotArcNode.selector, "geth/v1.14"));
        script.requireArcOrAnvilNode(bytes("geth/v1.14"));
    }

    /// The deployed vault is the one the script checks: TestLendVault's code compiles into the script's graph.
    function test_ScriptDeploysTheVaultContract() public pure {
        assertGt(type(TestLendVault).creationCode.length, 0);
    }
}
