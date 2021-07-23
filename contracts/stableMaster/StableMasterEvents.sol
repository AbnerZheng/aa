// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity 0.8.2;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import "../interfaces/IAgToken.sol";
import "../interfaces/ICollateralSettler.sol";
import "../interfaces/ICore.sol";
import "../interfaces/IFeeManager.sol";
import "../interfaces/IOracle.sol";
import "../interfaces/IPerpetualManager.sol";
import "../interfaces/IPoolManager.sol";
import "../interfaces/ISanToken.sol";
import "../interfaces/IStableMaster.sol";

import "../utils/FunctionUtils.sol";
import "../utils/PausableMapUpgradeable.sol";

/// @title StableMasterEvents
/// @author Angle Core Team
/// @notice `StableMaster` is the contract handling all the collateral types accepted for a given stablecoin
/// It does all the accounting and is the point of entry in the protocol for stable holders and seekers as well as SLPs
/// @dev This file contains all the events of the `StableMaster` contract
contract StableMasterEvents {
    event SanRateUpdated(uint256 _newSanRate, address indexed _token);

    event StocksUsersUpdated(address _token, int256 _stocksUsers);

    // ============================= Governors =====================================

    event CollateralDeployed(address _poolManager, address _perpetualManager, address _sanToken, address _oracle);

    event CollateralRevoked(address _poolManager);

    // ========================= Parameters update =================================

    event OracleUpdated(address _poolManager, address _oracle);

    event MaxSanRateUpdateUpdated(address _poolManager, uint256 _maxSanRateUpdate);

    event FeesForSLPsUpdated(address _poolManager, uint256 _feesForSLPs);

    event InterestsForSLPsUpdated(address _poolManager, uint256 _interestsForSLPs);

    event ArrayFeeMintUpdated(uint256[] _xFeeMint, uint256[] _yFeeMint);

    event ArrayFeeBurnUpdated(uint256[] _xFeeBurn, uint256[] _yFeeBurn);
}