// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

/// @title ISanToken
/// @author Angle Core Team
/// @notice Interface for Angle's `SanToken` contract, that handles sanTokens, tokens that are given to SLPs
/// contributing to a collateral for a given stablecoin
interface ISanToken is IERC20Upgradeable {
    // ================================== StableMaster =============================

    function mint(address account, uint256 amount) external;

    function burnFrom(
        uint256 amount,
        address burner,
        address sender
    ) external;

    function burnSelf(uint256 amount, address burner) external;
}