// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IAavePool} from "../interfaces/aave/IAavePool.sol";
import {IPriceOracleGetter} from "../interfaces/aave/IAavePriceGetter.sol";

import {IActionHandler} from "../interfaces/IActionHandler.sol";

/// @title AaveHandler
/// @author Shadow Protector, @parizval
/// @notice Handles all the logic for Aave Protocol Integration
contract AaveHandler is IActionHandler {
    // Storage
    IAavePool public immutable aavePool;
    IPriceOracleGetter public immutable aavePriceGetter;

    address public owner;

    // Events
    event UpdatedOwner(address oldOwner, address newOwner);

    // Errors
    error NotOwner(address sender, address owner);

    constructor(address _aavePool, address _aavePriceGetter) {
        owner = msg.sender;
        aavePool = IAavePool(_aavePool);
        aavePriceGetter = IPriceOracleGetter(_aavePriceGetter);
    }

    modifier OnlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender, owner);
        }
        _;
    }

    function updateOwner(address _newOwner) external OnlyOwner {
        emit UpdatedOwner(owner, _newOwner);
        owner = _newOwner;
    }

    function rescueFunds(address _token, uint256 _amount) external OnlyOwner {
        IERC20(_token).transfer(owner, _amount);
    }

    function evaluateCondition(
        uint16 _platform,
        address _platformAddress,
        address _borrower,
        uint16 _parameter,
        uint256 _conditionValue
    ) external view returns (bool) {
        if (_platform == 1) {
            return checkAavePortfioCondition(_borrower, _parameter, _conditionValue);
        } else if (_platform == 2) {
            return checkAaveCollateralCondition(_platformAddress, _borrower, _parameter, _conditionValue);
        } else if (_platform == 3) {
            return checkAaveDebtCondition(_platformAddress, _borrower, _parameter, _conditionValue);
        }

        return false;
    }

    function getDepositToken(address token, uint16 _assetType) external view returns (address) {
        if (_assetType == 1) {
            return aavePool.getReserveAToken(token);
        } else {
            return aavePool.getReserveVariableDebtToken(token);
        }
    }

    function unWindPosition(address depositToken, address baseToken, uint16, uint256 amount, address handler)
        external
        returns (uint256)
    {
        // Transfer Call from sender to this contract
        IERC20(depositToken).transferFrom(msg.sender, address(this), amount);

        return aavePool.withdraw(baseToken, amount, handler);
    }

    function handleDeposit(address token, uint256 amount, address _owner, bool repay, uint16) external {
        if (repay) {
            // Repay Function
            address variableDebtToken = aavePool.getReserveVariableDebtToken(token);

            uint256 debtBalance = IERC20(variableDebtToken).balanceOf(_owner);

            uint256 repayValue = amount;
            if (amount > debtBalance) {
                repayValue = debtBalance;
                IERC20(token).transfer(_owner, amount - debtBalance);
            }

            IERC20(token).approve(address(aavePool), repayValue);

            aavePool.repay(token, repayValue, 2, _owner);
        } else {
            // Supply Function
            IERC20(token).approve(address(aavePool), amount);
            aavePool.supply(token, amount, _owner, 0);
        }
    }

    function checkAavePortfioCondition(address _borrower, uint16 _parameter, uint256 conditionValue)
        public
        view
        returns (bool)
    {
        // Overall Portfolio Value
        (uint256 totalCollateralBase, uint256 totalDebtBase,,,, uint256 healthFactor) =
            aavePool.getUserAccountData(_borrower);

        // Check paramter is greater than totalCollateralBase
        if (_parameter == 0) {
            return totalCollateralBase > conditionValue;
        } // Check paramter is less or equal to totalCollateralBase
        else if (_parameter == 1) {
            return totalCollateralBase <= conditionValue;
        } // Check paramter is greater than totalDebtBase
        else if (_parameter == 2) {
            return totalDebtBase > conditionValue;
        } // Check paramter is less or equal to totalDebtBase
        else if (_parameter == 3) {
            return totalDebtBase <= conditionValue;
        } // Check parameter is greater than healthFactor
        else if (_parameter == 4) {
            return healthFactor > conditionValue;
        } // Check paramter is less or equal to healthFactor
        else if (_parameter == 5) {
            return healthFactor <= conditionValue;
        }

        return false;
    }

    function checkAaveDebtCondition(address _asset, address _borrower, uint16 _parameter, uint256 conditionValue)
        public
        view
        returns (bool)
    {
        uint256 assetUnit = 10 ** IERC20(_asset).decimals();
        uint256 assetPrice = aavePriceGetter.getAssetPrice(_asset);

        address variableDebtToken = aavePool.getReserveVariableDebtToken(_asset);

        uint256 debtBalance = IERC20(variableDebtToken).balanceOf(_borrower);

        uint256 debtBalanceInBaseCurrency = (debtBalance * assetPrice) / assetUnit;

        // Greater than asset Price
        if (_parameter == 0) {
            return assetPrice > conditionValue;
        } // Less than or equal to asset Price
        else if (_parameter == 1) {
            return assetPrice <= conditionValue;
        } // Greater than debt balance
        else if (_parameter == 2) {
            return debtBalance > conditionValue;
        } // Less than or equal to debt balance
        else if (_parameter == 3) {
            return debtBalance <= conditionValue;
        } // Greater than debt balance in base currency
        else if (_parameter == 4) {
            return debtBalanceInBaseCurrency > conditionValue;
        } // Less than or equal to debt balance in base currency
        else if (_parameter == 5) {
            return debtBalanceInBaseCurrency <= conditionValue;
        }

        return false;
    }

    function checkAaveCollateralCondition(address _asset, address _borrower, uint16 _parameter, uint256 conditionValue)
        public
        view
        returns (bool)
    {
        uint256 assetUnit = 10 ** IERC20(_asset).decimals();
        uint256 assetPrice = aavePriceGetter.getAssetPrice(_asset);

        address aToken = aavePool.getReserveAToken(_asset);

        uint256 collateralBalance = IERC20(aToken).balanceOf(_borrower);

        uint256 collateralBalanceInBaseCurrency = (collateralBalance * assetPrice) / assetUnit;

        // Greater than asset Price
        if (_parameter == 0) {
            return assetPrice > conditionValue;
        } // Less than or equal to asset Price
        else if (_parameter == 1) {
            return assetPrice <= conditionValue;
        } // Greater than debt balance
        else if (_parameter == 2) {
            return collateralBalance > conditionValue;
        } // Less than or equal to debt balance
        else if (_parameter == 3) {
            return collateralBalance <= conditionValue;
        } // Greater than debt balance in base currency
        else if (_parameter == 4) {
            return collateralBalanceInBaseCurrency > conditionValue;
        } // Less than or equal to debt balance in base currency
        else if (_parameter == 5) {
            return collateralBalanceInBaseCurrency <= conditionValue;
        }

        return false;
    }
}
