// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";

import {TestLendVault} from "../../src/TestLendVault.sol";
import {MockUsdc} from "../utils/MockUsdc.sol";

/// @dev A USDC stand-in with a FiatToken-style blocklist on msg.sender, from and to.
contract BlocklistUsdc is ERC20("USD Coin", "USDC") {
    mapping(address => bool) public blocked;

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function block_(address a) external {
        blocked[a] = true;
    }

    function _update(address from, address to, uint256 value) internal override {
        require(!blocked[msg.sender] && !blocked[from] && !blocked[to], "blocked");
        super._update(from, to, value);
    }
}

/// Audit PoCs, 13 Oct 2026. Uncommitted; each test states what it proves.
contract EarnAuditTest is Test {
    MockUsdc internal usdc;
    TestLendVault internal vault;
    address internal owner = makeAddr("owner");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal attacker = makeAddr("attacker");

    function setUp() public {
        usdc = new MockUsdc();
        vault = new TestLendVault(usdc, "Mercurifi Test Vault", "mtvUSDC", owner);
        address[4] memory who = [owner, alice, bob, attacker];
        for (uint256 i; i < who.length; ++i) {
            usdc.mint(who[i], 1e30);
            vm.prank(who[i]);
            usdc.approve(address(vault), type(uint256).max);
        }
    }

    /// EIP-4626: redeem(maxRedeem) and withdraw(maxWithdraw) never revert, for any limit, donation and share split,
    /// and the checked subtraction in `_withdraw` is unreachable from the public paths.
    function testFuzz_MaxPathsNeverRevert(uint96 a, uint96 b, uint96 donation, uint96 limit, bool viaRedeem) public {
        a = uint96(bound(a, 1, 1e18));
        b = uint96(bound(b, 1, 1e18));
        donation = uint96(bound(donation, 0, 1e18));
        vm.prank(alice);
        vault.deposit(a, alice);
        vm.prank(bob);
        vault.deposit(b, bob);
        vm.prank(attacker);
        usdc.transfer(address(vault), donation);
        vm.prank(owner);
        vault.setWithdrawLimit(limit);

        vm.startPrank(alice);
        if (viaRedeem) {
            uint256 s = vault.maxRedeem(alice);
            uint256 preview = vault.previewRedeem(s);
            uint256 got = vault.redeem(s, alice, alice);
            assertEq(got, preview, "previewRedeem == redeem");
        } else {
            uint256 w = vault.maxWithdraw(alice);
            uint256 preview = vault.previewWithdraw(w);
            uint256 burned = vault.withdraw(w, alice, alice);
            assertEq(burned, preview, "previewWithdraw == withdraw");
        }
        vm.stopPrank();
        assertLe(vault.withdrawLimit(), limit, "limit never rises on a payout");
    }

    /// EIP-4626: previews ignore the limit (as the standard requires); the call above max reverts with the OZ error.
    function test_PreviewIgnoresLimitAndCallReverts() public {
        vm.prank(alice);
        vault.deposit(100e6, alice);
        vm.prank(owner);
        vault.setWithdrawLimit(0);
        assertEq(vault.maxWithdraw(alice), 0);
        assertEq(vault.maxRedeem(alice), 0);
        assertEq(vault.previewRedeem(vault.balanceOf(alice)), 100e6);
        uint256 shares = vault.balanceOf(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(ERC4626.ERC4626ExceededMaxRedeem.selector, alice, shares, 0));
        vault.redeem(shares, alice, alice);
    }

    /// maxDeposit/maxMint stay unlimited while the limit is 0, and a deposit then funds the shared limit, which any
    /// holder can take first: the depositor can be left frozen (lending-pool bank-run semantics, by design).
    function test_FrozenVaultDepositLiquidityIsShared() public {
        vm.prank(bob);
        vault.deposit(100e6, bob);
        vm.prank(owner);
        vault.setWithdrawLimit(0);
        assertEq(vault.maxDeposit(alice), type(uint256).max);
        assertEq(vault.maxMint(alice), type(uint256).max);

        vm.prank(alice);
        vault.deposit(50e6, alice);
        assertEq(vault.withdrawLimit(), 50e6);
        // Bob back-runs Alice and takes the liquidity her deposit created.
        vm.prank(bob);
        vault.withdraw(50e6, bob, bob);
        assertEq(vault.maxWithdraw(alice), 0, "alice frozen behind her own deposit");
    }

    /// A set limit near the top saturates into the `type(uint256).max` sentinel, which switches the limit off.
    function test_SaturationFlipsToNoLimit() public {
        vm.prank(owner);
        vault.setWithdrawLimit(type(uint256).max - 1);
        vm.prank(alice);
        vault.deposit(10e6, alice);
        assertEq(vault.withdrawLimit(), type(uint256).max);
        // Payouts no longer lower it.
        vm.prank(alice);
        vault.withdraw(1e6, alice, alice);
        assertEq(vault.withdrawLimit(), type(uint256).max);
    }

    /// `fund` and plain donations raise totalAssets but not a set limit.
    function test_FundDoesNotRaiseASetLimit() public {
        vm.prank(alice);
        vault.deposit(100e6, alice);
        vm.startPrank(owner);
        vault.setWithdrawLimit(0);
        vault.fund(10e6);
        vm.stopPrank();
        assertEq(vault.withdrawLimit(), 0);
        assertEq(vault.maxWithdraw(alice), 0);
    }

    /// First-depositor inflation on an UNSEEDED vault: with a 6-decimal offset the attacker loses far more than the
    /// victim does. Attacker deposits 1 wei, donates D, victim deposits V.
    function test_InflationAttackUnprofitable() public {
        uint256 donation = 10_000e6;
        uint256 victimDeposit = 1_000e6;
        uint256 start = usdc.balanceOf(attacker);
        vm.startPrank(attacker);
        vault.deposit(1, attacker);
        usdc.transfer(address(vault), donation);
        vm.stopPrank();
        vm.prank(alice);
        uint256 shares = vault.deposit(victimDeposit, alice);
        assertGt(shares, 0, "victim still gets shares");
        uint256 attackerShares = vault.balanceOf(attacker);
        vm.prank(attacker);
        vault.redeem(attackerShares, attacker, attacker);
        uint256 attackerLoss = start - usdc.balanceOf(attacker);
        uint256 victimLoss = victimDeposit - vault.previewRedeem(vault.balanceOf(alice));
        emit log_named_uint("attacker loss", attackerLoss);
        emit log_named_uint("victim loss", victimLoss);
        assertGt(attackerLoss, 1_000 * victimLoss, "attack costs >1000x what it takes");
    }

    /// A one-transaction donation moves the share price the backend reads (APY display), at the donor's cost.
    function test_DonationMovesSharePrice() public {
        vm.prank(alice);
        vault.deposit(10e6, alice);
        uint256 one = 10 ** vault.decimals();
        uint256 before = vault.convertToAssets(one);
        vm.prank(attacker);
        usdc.transfer(address(vault), 1e6);
        assertApproxEqRel(vault.convertToAssets(one), before * 11 / 10, 1e14, "+10% share price for 1 USDC");
    }

    /// Blocklist: a holder whose address is blocked can still exit by redeeming to a clean receiver, and a blocked
    /// receiver only blocks that receiver. Generic to every ERC-4626 over USDC.
    function test_BlockedHolderRedeemsToCleanReceiver() public {
        BlocklistUsdc b = new BlocklistUsdc();
        TestLendVault v = new TestLendVault(b, "v", "v", owner);
        b.mint(alice, 100e6);
        vm.startPrank(alice);
        b.approve(address(v), type(uint256).max);
        v.deposit(100e6, alice);
        vm.stopPrank();
        b.block_(alice);
        vm.prank(alice);
        vm.expectRevert(bytes("blocked"));
        v.redeem(50e6 * 1e6, alice, alice);
        vm.prank(alice);
        v.redeem(50e6 * 1e6, bob, alice);
        assertEq(b.balanceOf(bob), 50e6);
        // A blocked vault freezes everyone.
        b.block_(address(v));
        vm.prank(alice);
        vm.expectRevert(bytes("blocked"));
        v.redeem(1e6, bob, alice);
    }
}
