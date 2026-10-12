// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {TestLendVault} from "../src/TestLendVault.sol";
import {DeployTestLendVault} from "../script/DeployTestLendVault.s.sol";

contract USDC6 is ERC20("USD Coin", "USDC") {
    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 a) external {
        _mint(to, a);
    }
}

contract TestLendVaultTest is Test {
    USDC6 usdc;
    TestLendVault vault;
    address owner = address(0xA11CE);
    address user = address(0xB0B);

    function setUp() public {
        usdc = new USDC6();
        vault = new TestLendVault(usdc, "Mercurifi Test Vault", "mtvUSDC", owner);
        usdc.mint(user, 1_000e6);
        usdc.mint(owner, 1_000e6);
        vm.prank(user);
        usdc.approve(address(vault), type(uint256).max);
    }

    // A deposit and a full withdrawal return the same assets when nothing was funded.
    function test_roundTrip() public {
        vm.startPrank(user);
        vault.deposit(100e6, user);
        vault.redeem(vault.balanceOf(user), user, user);
        vm.stopPrank();
        assertEq(usdc.balanceOf(user), 1_000e6);
    }

    // fund() raises the share price, which is what the backend's rate reads.
    function test_fundRaisesSharePrice() public {
        vm.prank(user);
        vault.deposit(100e6, user);
        uint256 one = 10 ** vault.decimals();
        uint256 before = vault.convertToAssets(one);
        vm.startPrank(owner);
        usdc.approve(address(vault), 1e6);
        vault.fund(1e6);
        vm.stopPrank();
        assertGt(vault.convertToAssets(one), before);
    }

    // The withdraw limit caps maxWithdraw and makes a larger withdraw revert, like a mostly-borrowed vault.
    function test_withdrawLimit() public {
        vm.prank(user);
        vault.deposit(100e6, user);
        vm.prank(owner);
        vault.setWithdrawLimit(10e6);
        assertEq(vault.maxWithdraw(user), 10e6);
        assertEq(vault.availableAssets(), 10e6);
        vm.prank(user);
        vm.expectRevert();
        vault.withdraw(11e6, user, user);
        vm.prank(user);
        vault.withdraw(10e6, user, user);
        assertEq(vault.availableAssets(), 0);
    }

    // Only the owner can fund or set the limit.
    function test_onlyOwner() public {
        vm.expectRevert();
        vault.setWithdrawLimit(1);
        vm.expectRevert();
        vault.fund(1);
    }

    // The deploy script refuses every chain but Arc testnet.
    function test_scriptRefusesMainnet() public {
        vm.chainId(5042);
        DeployTestLendVault s = new DeployTestLendVault();
        vm.expectRevert(bytes("TestLendVault: Arc testnet only"));
        s.run();
    }
}
