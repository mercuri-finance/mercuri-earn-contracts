// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC4626} from "@openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/access/Ownable.sol";
import {Math} from "@openzeppelin/utils/math/Math.sol";

/// @title TestLendVault
/// @notice ARC TESTNET ONLY. A plain ERC-4626 vault that stands in for a lending venue, because Arc testnet has no
///         Morpho or Aave. The owner simulates what borrowers would pay with fund(), and a mostly-borrowed vault with
///         setWithdrawLimit(). It lends nothing and must never be deployed to mainnet.
contract TestLendVault is ERC4626, Ownable {
    using SafeERC20 for IERC20;

    /// @notice What the vault can pay out now; type(uint256).max means no limit.
    uint256 public withdrawLimit = type(uint256).max;

    event Funded(uint256 assets);
    event WithdrawLimitSet(uint256 limit);

    constructor(IERC20 asset_, string memory name_, string memory symbol_, address owner_)
        ERC4626(asset_)
        ERC20(name_, symbol_)
        Ownable(owner_)
    {}

    /// @notice Adds assets without minting shares, so every share is worth more.
    function fund(uint256 assets) external onlyOwner {
        IERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);
        emit Funded(assets);
    }

    /// @notice Caps what can be withdrawn, like a vault whose deposits are mostly lent out.
    function setWithdrawLimit(uint256 limit) external onlyOwner {
        withdrawLimit = limit;
        emit WithdrawLimitSet(limit);
    }

    /// @notice What the vault can pay out now, across all holders.
    function availableAssets() public view returns (uint256) {
        return Math.min(totalAssets(), withdrawLimit);
    }

    function maxWithdraw(address owner_) public view override returns (uint256) {
        return Math.min(super.maxWithdraw(owner_), availableAssets());
    }

    function maxRedeem(address owner_) public view override returns (uint256) {
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

    /// @dev Offsets first-depositor inflation (OpenZeppelin virtual shares).
    function _decimalsOffset() internal pure override returns (uint8) {
        return 6;
    }
}
