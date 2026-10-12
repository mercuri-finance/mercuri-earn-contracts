// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {TestLendVault} from "../../src/TestLendVault.sol";
import {MockUsdc} from "../utils/MockUsdc.sol";

/// @notice Drives the vault with holders depositing, withdrawing and redeeming, the owner funding and setting limits,
///         and outsiders donating, every call bounded so it should succeed. Keeps a model of the withdraw limit.
contract TestLendVaultHandler is Test {
    TestLendVault internal immutable vault;
    MockUsdc internal immutable usdc;
    address internal immutable owner;
    address[3] internal actors;

    /// The limit the vault should hold: owner sets, plus deposits, minus payouts, saturating at no limit.
    uint256 public modelLimit = type(uint256).max;
    /// The highest share price seen; the price must never fall.
    uint256 public highestPrice;
    uint256 public calls;

    constructor(TestLendVault vault_, MockUsdc usdc_, address owner_) {
        vault = vault_;
        usdc = usdc_;
        owner = owner_;
        for (uint256 i; i < actors.length; ++i) {
            actors[i] = makeAddr(string.concat("holder", vm.toString(i)));
            vm.prank(actors[i]);
            usdc.approve(address(vault), type(uint256).max);
        }
        vm.prank(owner);
        usdc.approve(address(vault), type(uint256).max);
        highestPrice = vault.convertToAssets(10 ** vault.decimals());
    }

    function actor(uint256 seed) public view returns (address) {
        return actors[seed % actors.length];
    }

    function deposit(uint256 seed, uint256 assets) external {
        assets = bound(assets, 1, 1_000_000e6);
        address who = actor(seed);
        usdc.mint(who, assets);
        vm.prank(who);
        vault.deposit(assets, who);
        if (modelLimit != type(uint256).max) {
            modelLimit = assets > type(uint256).max - modelLimit ? type(uint256).max : modelLimit + assets;
        }
        _track();
    }

    function withdraw(uint256 seed, uint256 assets) external {
        address who = actor(seed);
        uint256 max = vault.maxWithdraw(who);
        if (max == 0) return;
        assets = bound(assets, 1, max);
        vm.prank(who);
        vault.withdraw(assets, who, who);
        if (modelLimit != type(uint256).max) modelLimit -= assets;
        _track();
    }

    function redeem(uint256 seed, uint256 shares) external {
        address who = actor(seed);
        uint256 max = vault.maxRedeem(who);
        if (max == 0) return;
        shares = bound(shares, 1, max);
        uint256 assets = vault.previewRedeem(shares);
        vm.prank(who);
        uint256 paid = vault.redeem(shares, who, who);
        assertEq(paid, assets, "redeem paid what previewRedeem said");
        if (modelLimit != type(uint256).max) modelLimit -= paid;
        _track();
    }

    function fund(uint256 assets) external {
        assets = bound(assets, 1, 100_000e6);
        usdc.mint(owner, assets);
        vm.prank(owner);
        vault.fund(assets);
        _track();
    }

    function donate(uint256 assets) external {
        assets = bound(assets, 1, 100_000e6);
        usdc.mint(address(vault), assets);
        _track();
    }

    function setWithdrawLimit(uint256 limit, bool unlimited) external {
        limit = unlimited ? type(uint256).max : bound(limit, 0, vault.totalAssets() + 1_000e6);
        vm.prank(owner);
        vault.setWithdrawLimit(limit);
        modelLimit = limit;
        _track();
    }

    function _track() internal {
        ++calls;
        uint256 price = vault.convertToAssets(10 ** vault.decimals());
        if (price > highestPrice) highestPrice = price;
    }
}

contract TestLendVaultInvariantsTest is Test {
    TestLendVault internal vault;
    MockUsdc internal usdc;
    TestLendVaultHandler internal handler;

    function setUp() public {
        usdc = new MockUsdc();
        address owner = makeAddr("owner");
        vault = new TestLendVault(usdc, "Mercurifi Test Vault", "mtvUSDC", owner);
        handler = new TestLendVaultHandler(vault, usdc, owner);
        targetContract(address(handler));
        bytes4[] memory selectors = new bytes4[](6);
        selectors[0] = TestLendVaultHandler.deposit.selector;
        selectors[1] = TestLendVaultHandler.withdraw.selector;
        selectors[2] = TestLendVaultHandler.redeem.selector;
        selectors[3] = TestLendVaultHandler.fund.selector;
        selectors[4] = TestLendVaultHandler.donate.selector;
        selectors[5] = TestLendVaultHandler.setWithdrawLimit.selector;
        targetSelector(FuzzSelector({addr: address(handler), selectors: selectors}));
    }

    /// The vault's limit is exactly the model: owner sets, plus deposits, minus payouts.
    function invariant_LimitMatchesTheModel() public view {
        assertEq(vault.withdrawLimit(), handler.modelLimit());
    }

    /// Nobody can withdraw more than the vault can pay out, and it never pays out more than it holds.
    function invariant_PayoutsAreBounded() public view {
        uint256 available = vault.availableAssets();
        assertLe(available, vault.totalAssets());
        assertLe(available, vault.withdrawLimit());
        for (uint256 i; i < 3; ++i) {
            address who = handler.actor(i);
            assertLe(vault.maxWithdraw(who), available);
            assertLe(vault.previewRedeem(vault.maxRedeem(who)), available);
        }
    }

    /// The share price never falls: rounding favours the vault and payouts are proportional.
    function invariant_SharePriceNeverFalls() public view {
        assertEq(vault.convertToAssets(10 ** vault.decimals()), handler.highestPrice());
    }

    /// The vault's assets are exactly its USDC balance.
    function invariant_AssetsAreTheBalance() public view {
        assertEq(vault.totalAssets(), usdc.balanceOf(address(vault)));
    }

    /// Exported so a campaign shows its calls actually landed.
    function afterInvariant() public view {
        assertGt(handler.calls(), 0);
    }
}
