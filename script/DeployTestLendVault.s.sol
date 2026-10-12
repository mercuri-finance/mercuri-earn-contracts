// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console2} from "forge-std/Script.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {TestLendVault} from "../src/TestLendVault.sol";

/// @notice Deploys the Earn test vault on Arc testnet. Refuses every other chain.
contract DeployTestLendVault is Script {
    // Arc's USDC ERC-20 interface (6 decimals).
    IERC20 constant USDC = IERC20(0x3600000000000000000000000000000000000000);

    function run() external returns (TestLendVault vault) {
        require(block.chainid == 5042002, "TestLendVault: Arc testnet only");
        address owner = vm.envAddress("EARN_TEST_VAULT_OWNER");
        vm.startBroadcast();
        vault = new TestLendVault(USDC, "Mercurifi Test Vault", "mtvUSDC", owner);
        vm.stopBroadcast();
        console2.log("TestLendVault", address(vault), "block", block.number);
    }
}
