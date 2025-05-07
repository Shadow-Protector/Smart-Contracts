// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

import {IAavePool} from "./interfaces/IAavePool.sol";
import {IPriceOracleGetter} from "./interfaces/IAavePriceGetter.sol";

import {IOracle} from "./interfaces/IMorphoOracle.sol";
import {IMorpho} from "./interfaces/IMorpho.sol";
// Condition parameters (32 bytes)
// -> (platform type) (type = number)
//   -> Chainlink for prices
//   -> Aave Vault Parameters
//   -> Morpho Vault Parameters
//   -> Euler labs Parameters
// -> (Vault or Token Addres) (type = address) (20 bytes )
//   -> Chainlink (Token address for price feed) (Generic)
//   -> Aave Pool Parameters (Reserve Token address)
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
    address public immutable owner;

    address public immutable aavePool;
    address public immutable aavePriceGetter;
    address public immutable eulerPool;
    address public immutable morphoPool;

    // Mappings
    mapping(address => bytes32) public morphoVaults;

    constructor(address _aavePool, address _morphoPool) {
        owner = msg.sender;
        aavePool = _aavePool;
        morphoPool = _morphoPool;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function addMorphoVault(address _vault, bytes32 _vaultId) external onlyOwner {
        morphoVaults[_vault] = _vaultId;
    }

    function evaluateCondition(
        uint16 _platform,
        address _platformAddress,
        address _borrower,
        uint16 _parameter,
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
            return checkMorphoCondition(_platformAddress, _borrower, _parameter, _conditionValue);
        } else if (_platform == 5) {
            return checkEulerCondition();
        } else {
            return false;
        }
    }

    function checkChainlinkCondition(address _V3InterfaceAddress, uint16 parameter, uint256 conditionValue)
        public
        view
        returns (bool)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_V3InterfaceAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 priceValue = uint256(price);
        uint256 priceDecimals = 10 ** priceFeed.decimals();

        uint256 PriceWithTwoDecimals = (priceValue * 100) / priceDecimals;

        // Greater than Value
        if (parameter == 0) {
            return conditionValue > PriceWithTwoDecimals;
        }
        // Less than Value or equal to
        else if (parameter == 1) {
            return conditionValue <= PriceWithTwoDecimals;
        }

        return false;
    }

    function checkAavePortfioCondition(address _borrower, uint16 _parameter, uint256 conditionValue)
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
        } // Check paramter is greater than healthFactor
        else if (_parameter == 6) {
            return conditionValue > healthFactor;
        } // Check paramter is less or equal to healthFactor
        else if (_parameter == 7) {
            return conditionValue <= healthFactor;
        }

        return false;
    }

    function checkAaveDebtCondition(address _asset, address _borrower, uint16 _parameter, uint256 conditionValue)
        public
        view
        returns (bool)
    {
        uint256 assetUnit = 10 ** IERC20(_asset).decimals();
        uint256 assetPrice = IPriceOracleGetter(aavePriceGetter).getAssetPrice(_asset);

        address variableDebtToken = IAavePool(aavePool).getReserveVariableDebtToken(_asset);

        uint256 debtBalance = IERC20(variableDebtToken).balanceOf(_borrower);

        uint256 debtBalanceInBaseCurrency = (debtBalance * assetPrice) / assetUnit;

        // Greater than asset Price
        if (_parameter == 0) {
            return conditionValue > assetPrice;
        } // Less than or equal to asset Price
        else if (_parameter == 1) {
            return conditionValue <= assetPrice;
        } // Greater than debt balance
        else if (_parameter == 2) {
            return conditionValue > debtBalance;
        } // Less than or equal to debt balance
        else if (_parameter == 3) {
            return conditionValue <= debtBalance;
        } // Greater than debt balance in base currency
        else if (_parameter == 4) {
            return conditionValue > debtBalanceInBaseCurrency;
        } // Less than or equal to debt balance in base currency
        else if (_parameter == 5) {
            return conditionValue <= debtBalanceInBaseCurrency;
        }

        return false;
    }

    function checkAaveCollateralCondition(address _asset, address _borrower, uint16 _parameter, uint256 conditionValue)
        public
        view
        returns (bool)
    {
        uint256 assetUnit = 10 ** IERC20(_asset).decimals();
        uint256 assetPrice = IPriceOracleGetter(aavePriceGetter).getAssetPrice(_asset);

        address aToken = IAavePool(aavePool).getReserveAToken(_borrower);

        uint256 collateralBalance = IERC20(aToken).balanceOf(_borrower);

        uint256 collateralBalanceInBaseCurrency = (collateralBalance * assetPrice) / assetUnit;

        // Greater than asset Price
        if (_parameter == 0) {
            return conditionValue > assetPrice;
        } // Less than or equal to asset Price
        else if (_parameter == 1) {
            return conditionValue <= assetPrice;
        } // Greater than debt balance
        else if (_parameter == 2) {
            return conditionValue > collateralBalance;
        } // Less than or equal to debt balance
        else if (_parameter == 3) {
            return conditionValue <= collateralBalance;
        } // Greater than debt balance in base currency
        else if (_parameter == 4) {
            return conditionValue > collateralBalanceInBaseCurrency;
        } // Less than or equal to debt balance in base currency
        else if (_parameter == 5) {
            return conditionValue <= collateralBalanceInBaseCurrency;
        }

        return false;
    }

    function checkMorphoCondition(address _market, address _borrower, uint16 _parameter, uint256 conditionValue)
        public
        view
        returns (bool)
    {}

    function checkEulerCondition() public view returns (bool) {}
}
