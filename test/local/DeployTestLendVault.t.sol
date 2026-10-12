// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {DeployTestLendVault} from "../../script/DeployTestLendVault.s.sol";
import {EarnDeployBase} from "../../script/EarnDeployBase.sol";
import {TestLendVault} from "../../src/TestLendVault.sol";
import {MockUsdc} from "../utils/MockUsdc.sol";

contract DeployTestLendVaultHarness is DeployTestLendVault {
    function runWith(string memory path) external returns (TestLendVault) {
        _requireArcTestnet();
        return _deploy(_readManifest(path));
    }

    function requireArcOrAnvilNode(bytes memory clientVersion) external pure {
        _requireArcOrAnvilNode(clientVersion);
    }
}

contract EighteenDecimals {
    function decimals() external pure returns (uint8) {
        return 18;
    }
}

contract DeployTestLendVaultTest is Test {
    address internal constant USDC = 0x3600000000000000000000000000000000000000;
    address internal constant FIXTURE_OWNER = 0x00000000000000000000000000000000000000A1;

    DeployTestLendVaultHarness internal script;

    function setUp() public {
        script = new DeployTestLendVaultHarness();
    }

    function _arcTestnetWithUsdc() internal {
        vm.chainId(5042002);
        vm.etch(USDC, address(new MockUsdc()).code);
    }

    /// The script refuses Arc mainnet and every other chain.
    function test_RefusesEveryChainButTestnet() public {
        vm.chainId(5042);
        vm.expectRevert(abi.encodeWithSelector(EarnDeployBase.WrongChain.selector, 5042));
        script.run();
    }

    /// The script refuses a manifest with no owner: a vault nobody controls.
    function test_RefusesAZeroOwner() public {
        _arcTestnetWithUsdc();
        vm.expectRevert(abi.encodeWithSelector(EarnDeployBase.ManifestMismatch.selector, "owner"));
        script.runWith("test/fixtures/manifest-zero-owner.json");
    }

    /// A broadcast must reach an Arc node or a loopback Anvil fork.
    function test_AcceptsOnlyArcOrAnvilNodes() public {
        script.requireArcOrAnvilNode(bytes("arc/v1.0.0"));
        script.requireArcOrAnvilNode(bytes('"anvil/v1.4.3"'));
        vm.expectRevert(abi.encodeWithSelector(EarnDeployBase.NotArcNode.selector, "geth/v1.14"));
        script.requireArcOrAnvilNode(bytes("geth/v1.14"));
    }

    /// With a complete manifest the script deploys the vault, wires it as named and seeds it in the same broadcast, so
    /// no donation can land on an empty vault before its first deposit.
    function test_DeploysAndSeedsFromTheManifest() public {
        _arcTestnetWithUsdc();
        MockUsdc(USDC).mint(DEFAULT_SENDER, 100e6);
        TestLendVault vault = script.runWith("test/fixtures/manifest-5042002.json");
        assertEq(vault.asset(), USDC);
        assertEq(vault.owner(), FIXTURE_OWNER);
        assertEq(vault.totalAssets(), 100e6);
        assertEq(vault.balanceOf(FIXTURE_OWNER), vault.convertToShares(100e6));
    }

    /// The script refuses an asset other than Arc's USDC.
    function test_RefusesAnotherAsset() public {
        _arcTestnetWithUsdc();
        vm.expectRevert(abi.encodeWithSelector(EarnDeployBase.ManifestMismatch.selector, "asset"));
        script.runWith("test/fixtures/manifest-wrong-asset.json");
    }

    /// The script refuses an asset whose decimals are not USDC's six.
    function test_RefusesWrongDecimals() public {
        vm.chainId(5042002);
        vm.etch(USDC, address(new EighteenDecimals()).code);
        vm.expectRevert(abi.encodeWithSelector(EarnDeployBase.ManifestMismatch.selector, "decimals"));
        script.runWith("test/fixtures/manifest-5042002.json");
    }
}
