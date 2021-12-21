pragma solidity ^0.8.7;
pragma experimental ABIEncoderV2;
import "../interfaces/IPoolManager.sol";
import "./StableMaster.sol";
import "./StableMasterStorage.sol";
import "../utils/FunctionUtils.sol";
import "../interfaces/IStableMaster.sol";

contract StableMasterQuery is FunctionUtils {
    function _computeHedgeRatio(uint256 newStocksUsers, StableMaster.Collateral memory col) internal view returns (uint64 ratio) {
        // Fetching the amount hedged by HAs from the corresponding `perpetualManager` contract
        uint256 totalHedgeAmount = col.perpetualManager.totalHedgeAmount();
        newStocksUsers = (col.feeData.targetHAHedge * newStocksUsers) / BASE_PARAMS;
        if (newStocksUsers > totalHedgeAmount) ratio = uint64((totalHedgeAmount * BASE_PARAMS) / newStocksUsers);
        else ratio = uint64(BASE_PARAMS);
    }
    function _computeFeeMint(uint256 amount, StableMaster.Collateral memory col) internal view returns (uint256 feeMint) {
        uint64 feeMint64;
        if (col.feeData.xFeeMint.length == 1) {
            // This is done to avoid an external call in the case where the fees are constant regardless of the collateral
            // ratio
            feeMint64 = col.feeData.yFeeMint[0];
        } else {
            uint64 hedgeRatio = _computeHedgeRatio(amount + col.stocksUsers, col);
            // Computing the fees based on the spread
            feeMint64 = _piecewiseLinear(hedgeRatio, col.feeData.xFeeMint, col.feeData.yFeeMint);
        }
        // Fees could in some occasions depend on other factors like collateral ratio
        // Keepers are the ones updating this part of the fees
        feeMint = (feeMint64 * col.feeData.bonusMalusMint) / BASE_PARAMS;
    }

    function getCollateral(IPoolManager poolManager) internal view returns (StableMaster.Collateral memory) {
        (IERC20 token, ISanToken sanToken, IPerpetualManager perpetualManager, IOracle oracle, uint256 stocksUsers, uint256 sanRate,uint256 collatBase, SLPData memory slpData,  MintBurnData memory feeData) = stableMaster.collateralMap(poolManager);
        return StableMasterStorage.Collateral(token, sanToken, perpetualManager, oracle, stocksUsers, sanRate, collatBase, slpData, feeData);
    }

    function mintQuery(
        uint256 amount,
        address poolManager
    ) external view returns (uint256) {
        StableMaster.Collateral memory col = getCollateral(IPoolManager(poolManager));
        if (address(col.token) == address(0)) {
            return 0;
        }
        bytes32 target = keccak256(abi.encodePacked(agent, address(poolManager)));
        if (stableMaster.paused(target)) {
            return 0;
        }
        uint256 amountForUserInStable = col.oracle.readQuoteLower(amount);

        uint256 fees = _computeFeeMint(amountForUserInStable, col);

        amountForUserInStable = (amountForUserInStable * (BASE_PARAMS - fees)) / BASE_PARAMS;

        col.stocksUsers += amountForUserInStable;
        if (col.stocksUsers > col.feeData.capOnStableMinted) {
            return 0;
        }

        return amountForUserInStable;
    }



    StableMaster constant internal stableMaster = StableMaster(0x5adDc89785D75C86aB939E9e15bfBBb7Fc086A87);
    bytes32 constant internal agent = keccak256("STABLE");
}
