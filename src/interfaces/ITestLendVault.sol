// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @notice An ERC-4626 vault that stands in for a lending venue on Arc testnet, where no lending protocol is deployed.
/// @dev Arc testnet only. The vault lends nothing: the owner simulates what borrowers would pay with `fund` and a
///      mostly-lent-out vault with `setWithdrawLimit`.
interface ITestLendVault is IERC4626 {
    /// @notice Ownership cannot be renounced: with a zero withdraw limit and no owner, holders' assets would be frozen
    ///         for good.
    error RenounceDisabled();

    /// @notice The owner added assets without minting shares, raising the value of every share.
    /// @param assets The assets added, in the asset's base units.
    event Funded(uint256 assets);

    /// @notice The owner set what the vault can pay out across all holders.
    /// @param limit The new limit in the asset's base units; `type(uint256).max` means no limit.
    event WithdrawLimitSet(uint256 limit);

    /// @notice Adds assets from the owner without minting shares, so every share is worth more.
    /// @dev Pulls `assets` from the caller with `transferFrom`; the caller must have approved the vault.
    /// @param assets The assets to add, in the asset's base units.
    function fund(uint256 assets) external;

    /// @notice Caps what the vault can pay out across all holders, like a vault whose deposits are mostly lent out.
    /// @dev Every withdrawal lowers the remaining limit by the assets paid out.
    /// @param limit The new limit in the asset's base units; `type(uint256).max` removes it.
    function setWithdrawLimit(uint256 limit) external;

    /// @notice What the vault can still pay out across all holders.
    /// @return The limit in the asset's base units; `type(uint256).max` means no limit.
    function withdrawLimit() external view returns (uint256);

    /// @notice What the vault can pay out now, across all holders: its assets, capped by the withdraw limit.
    /// @return The assets that can be withdrawn now, in the asset's base units.
    function availableAssets() external view returns (uint256);
}
