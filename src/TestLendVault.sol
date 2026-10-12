// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

import {ITestLendVault} from "./interfaces/ITestLendVault.sol";

/// @notice Arc testnet only: a plain ERC-4626 vault over USDC that stands in for a lending venue, because Arc testnet
///         has no Morpho or Aave. It lends nothing and must never be deployed to mainnet.
/// @dev Immutable; no proxy and no upgrade path. The owner (two-step transfer) can only add assets (`fund`) and cap
///      payouts (`setWithdrawLimit`); it cannot move holders' assets. A zero limit stops every withdrawal, which is
///      the point of simulating a fully lent-out vault. Replacement is a new deployment and a registry change.
contract TestLendVault is ERC4626, Ownable2Step, ITestLendVault {
    using SafeERC20 for IERC20;

    /// @inheritdoc ITestLendVault
    uint256 public withdrawLimit = type(uint256).max;

    /// @notice Creates the vault over `asset_`, owned by `owner_`.
    /// @param asset_ The asset deposited, USDC on Arc testnet.
    /// @param name_ The share token's name.
    /// @param symbol_ The share token's symbol.
    /// @param owner_ The account that may fund the vault and set its withdraw limit.
    constructor(IERC20 asset_, string memory name_, string memory symbol_, address owner_)
        ERC4626(asset_)
        ERC20(name_, symbol_)
        Ownable(owner_)
    {}

    /// @inheritdoc ITestLendVault
    function fund(uint256 assets) external onlyOwner {
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        emit Funded(assets);
    }

    /// @inheritdoc ITestLendVault
    function setWithdrawLimit(uint256 limit) external onlyOwner {
        withdrawLimit = limit;
        emit WithdrawLimitSet(limit);
    }

    /// @inheritdoc ITestLendVault
    function availableAssets() public view returns (uint256) {
        return Math.min(totalAssets(), withdrawLimit);
    }

    /// @notice What `owner_` can withdraw now: its shares' value, capped by what the vault can pay out.
    /// @param owner_ The share holder.
    /// @return The assets `owner_` can withdraw now, in the asset's base units.
    function maxWithdraw(address owner_) public view override(ERC4626, IERC4626) returns (uint256) {
        return Math.min(super.maxWithdraw(owner_), availableAssets());
    }

    /// @notice The shares `owner_` can redeem now: its shares, capped by what the vault can pay out.
    /// @param owner_ The share holder.
    /// @return The shares `owner_` can redeem now.
    function maxRedeem(address owner_) public view override(ERC4626, IERC4626) returns (uint256) {
        return Math.min(super.maxRedeem(owner_), convertToShares(availableAssets()));
    }

    /// @dev Every payout lowers the remaining limit, so the limit behaves like idle liquidity.
    function _withdraw(address caller, address receiver, address owner_, uint256 assets, uint256 shares)
        internal
        override
    {
        if (withdrawLimit != type(uint256).max) withdrawLimit -= assets;
        super._withdraw(caller, receiver, owner_, assets, shares);
    }

    /// @dev Six virtual decimals of shares offset first-depositor inflation (OpenZeppelin virtual shares).
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }
}
