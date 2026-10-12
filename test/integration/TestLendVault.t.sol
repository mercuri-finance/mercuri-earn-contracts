// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {TestLendVault} from "../../src/TestLendVault.sol";
import {ITestLendVault} from "../../src/interfaces/ITestLendVault.sol";
import {MockUsdc} from "../utils/MockUsdc.sol";

contract TestLendVaultTest is Test {
    MockUsdc internal usdc;
    TestLendVault internal vault;
    address internal owner = makeAddr("owner");
    address internal user = makeAddr("user");

    function setUp() public {
        usdc = new MockUsdc();
        vault = new TestLendVault(usdc, "Mercurifi Test Vault", "mtvUSDC", owner);
        usdc.mint(user, 1_000e6);
        usdc.mint(owner, 1_000e6);
        vm.prank(user);
        usdc.approve(address(vault), type(uint256).max);
    }

    /// A deposit and a full redemption return the same assets when nothing was funded.
    function test_RoundTripReturnsTheDeposit() public {
        vm.startPrank(user);
        vault.deposit(100e6, user);
        vault.redeem(vault.balanceOf(user), user, user);
        vm.stopPrank();
        assertEq(usdc.balanceOf(user), 1_000e6);
    }

    /// `fund` raises the share price, which is what the backend's rate reads.
    function test_FundRaisesSharePrice() public {
        vm.prank(user);
        vault.deposit(100e6, user);
        uint256 one = 10 ** vault.decimals();
        uint256 before = vault.convertToAssets(one);
        vm.startPrank(owner);
        usdc.approve(address(vault), 1e6);
        vm.expectEmit(address(vault));
        emit ITestLendVault.Funded(1e6);
        vault.fund(1e6);
        vm.stopPrank();
        assertGt(vault.convertToAssets(one), before);
    }

    /// The withdraw limit caps maxWithdraw and maxRedeem, a larger withdrawal reverts, and each payout lowers it.
    function test_WithdrawLimitCapsPayouts() public {
        vm.prank(user);
        vault.deposit(100e6, user);
        vm.prank(owner);
        vault.setWithdrawLimit(10e6);
        assertEq(vault.maxWithdraw(user), 10e6);
        assertEq(vault.availableAssets(), 10e6);
        assertEq(vault.maxRedeem(user), vault.convertToShares(10e6));
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxWithdraw.selector, user, 11e6, 10e6));
        vault.withdraw(11e6, user, user);
        vm.prank(user);
        vault.withdraw(10e6, user, user);
        assertEq(vault.availableAssets(), 0);
    }

    /// Only the owner can fund or set the limit.
    function test_OnlyOwnerFundsAndLimits() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.setWithdrawLimit(1);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        vault.fund(1);
    }

    /// Ownership moves in two steps: the new owner has nothing until it accepts.
    function test_OwnershipTransferIsTwoStep() public {
        address next = makeAddr("next");
        vm.prank(owner);
        vault.transferOwnership(next);
        assertEq(vault.owner(), owner);
        vm.prank(next);
        vault.acceptOwnership();
        assertEq(vault.owner(), next);
    }

    /// No deposit or withdrawal sequence leaves holders able to withdraw more than the vault holds.
    function testFuzz_MaxWithdrawNeverExceedsAssets(uint96 deposit, uint96 limit) public {
        uint256 amount = bound(deposit, 1, 1_000e6);
        vm.prank(user);
        vault.deposit(amount, user);
        vm.prank(owner);
        vault.setWithdrawLimit(limit);
        assertLe(vault.maxWithdraw(user), vault.totalAssets());
        assertLe(vault.maxWithdraw(user), limit);
    }
}
