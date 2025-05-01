// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

import {IAavePool} from "./interfaces/IAavePool.sol";

// Condition parameters (32 bytes)
// -> (platform type) (type = number)
//   -> Chainlink for prices
//   -> Aave Vault Parameters
//   -> Morpho Vault Parameters
//   -> Euler labs Parameters
// -> (Vault or Token Addres) (type = address) (20 bytes )
//   -> Chainlink (Token address for price feed) (Generic)
//   -> Aave Pool Parameters (Pool Address or Vault (!TODO))
//   -> Morpho Vault (address) (Single Contract each chain)
//   -> Euler Vault For Evaulation
// -> (Parameter Categorization) (type = number )
//   -> Chainlink (Lower or Greater )
//   -> Aave (Collateral Value, other params )
//   -> Morpho Params
//   -> Euler Valut parameters
// -> Condition Value (type number) (uint256) (Stored inside the struct)
//   -> Asset Price Value in 18 decimals
//   -> Aave Values
//   -> Morpho Values
//   -> Euler Values

contract ConditionEvaulator {
    address public immutable aavePool;
    address public immutable morphoPool;
    address public immutable eulerPool;

    constructor(address _aavePool, address _morphoPool) {
        aavePool = _aavePool;
        morphoPool = _morphoPool;
    }

    function evaluateCondition(
        uint8 _platform,
        address _platformAddress,
        address _borrower,
        uint8 _parameter,
        uint256 _conditionValue
    ) public view returns (bool) {
        if (_platform == 0) {
            return checkChainlinkCondition(_platformAddress, _parameter, _conditionValue);
        } else if (_platform == 1) {
            return checkAavePortfioCondition(_borrower, _parameter, _conditionValue);
        } else if (_platform == 2) {
            return checkAaveCollateralCondition(_platformAddress, _borrower, _parameter, _conditionValue);
        } else if (_platform == 3) {
            return checkAaveCollateralCondition(_platformAddress, _borrower, _parameter, _conditionValue);
        } else if (_platform == 4) {
            return checkMorphoCondition();
        } else if (_platform == 5) {
            return checkEulerCondition();
        } else {
            return false;
        }
    }

    function checkChainlinkCondition(address _V3InterfaceAddress, uint8 parameter, uint256 conditionValue)
        public
        view
        returns (bool)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_V3InterfaceAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 priceValue = uint256(price);

        // Greater than Value
        if (parameter == 0) {
            return conditionValue > priceValue;
        }
        // Less than Value or equal to
        else if (parameter == 1) {
            return conditionValue <= priceValue;
        }

        return false;
    }

    function checkAavePortfioCondition(address _borrower, uint8 _parameter, uint256 conditionValue)
        public
        view
        returns (bool)
    {
        // Overall Portfolio Value
        (uint256 totalCollateralBase, uint256 totalDebtBase,,, uint256 ltv, uint256 healthFactor) =
            IAavePool(aavePool).getUserAccountData(_borrower);

        // Check paramter is greater than totalCollateralBase
        if (_parameter == 0) {
            return conditionValue > totalCollateralBase;
        } // Check paramter is less or equal to totalCollateralBase
        else if (_parameter == 1) {
            return conditionValue <= totalCollateralBase;
        } // Check paramter is greater than totalDebtBase
        else if (_parameter == 2) {
            return conditionValue > totalDebtBase;
        } // Check paramter is less or equal to totalDebtBase
        else if (_parameter == 3) {
            return conditionValue <= totalDebtBase;
        } // Check paramter is greater than ltv
        else if (_parameter == 4) {
            return conditionValue > ltv;
        } // Check paramter is less or equal to ltv
        else if (_parameter == 5) {
            return conditionValue <= ltv;
        } else if (_parameter == 6) {
            return conditionValue > healthFactor;
        } else if (_parameter == 7) {
            return conditionValue <= healthFactor;
        }

        return false;
    }

    function checkAaveDebtCondition(address _asset, address _borrower, uint8 _parameter, uint256 conditionValue)
        public
        view
        returns (bool)
    {}

    function checkAaveCollateralCondition(address _asset, address _borrower, uint8 _parameter, uint256 conditionValue)
        public
        view
        returns (bool)
    {}

    function checkMorphoCondition() public view returns (bool) {}

    function checkEulerCondition() public view returns (bool) {}
}
