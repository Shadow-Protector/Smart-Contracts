// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

import {IAavePool} from "./interfaces/aave/IAavePool.sol";
import {IPriceOracleGetter} from "./interfaces/aave/IAavePriceGetter.sol";

import {IOracle} from "./interfaces/morpho/IMorphoOracle.sol";
import {IMorpho, MarketParams, Id, Position, Market} from "../src/interfaces/morpho/IMorpho.sol";
import {MathLib, WAD} from "./lib/MathLib.sol";
import {SharesMathLib} from "./lib/SharesMathLib.sol";

import {IRouter} from "./interfaces/aerodrome/IRouter.sol";

import {IVault, OrderExecutionDetails} from "./interfaces/IVault.sol";

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

contract Handler {
    using MathLib for uint256;
    using SharesMathLib for uint256;

    address public owner;

    IAavePool public immutable aavePool;
    IPriceOracleGetter public immutable aavePriceGetter;

    IMorpho public immutable morphoPool;

    // Aerodrome Router
    IRouter public immutable aerodromeRouter;

    address public immutable eulerPool;

    // Mappings
    mapping(address => bytes32) public morphoMarket;
    mapping(address => address) public morphoVaults;
    mapping(address => address) public eulerDepositVaults;

    // Events
    event UpdatedOwner(address oldOwner, address newOwner);

    // Errors
    error InvalidRoute();
    error InvalidStartToken(address requiredToken, address startToken);
    error InvalidEndToken(address requiredToken, address endToken);

    constructor(address _aavePool, address _aavePriceGetter, address _morphoPool, address _aerodromeRouter) {
        owner = msg.sender;
        aavePool = IAavePool(_aavePool);
        aavePriceGetter = IPriceOracleGetter(_aavePriceGetter);
        morphoPool = IMorpho(_morphoPool);
        aerodromeRouter = IRouter(_aerodromeRouter);
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function updateOwner(address _newOwner) external onlyOwner {
        emit UpdatedOwner(owner, _newOwner);
        owner = _newOwner;
    }

    function addMorphoMarket(address _market, bytes32 _id) external onlyOwner {
        morphoMarket[_market] = _id;
    }

    function addMorphoVault(address _vault, address _vaultId) external onlyOwner {
        morphoVaults[_vault] = _vaultId;
    }

    function rescueFunds(address _token, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(owner, _amount);
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
            return checkAaveDebtCondition(_platformAddress, _borrower, _parameter, _conditionValue);
        } else if (_platform == 4) {
            return checkMorphoCondition(_platformAddress, _borrower, _parameter, _conditionValue);
        } else if (_platform == 5) {
            return checkEulerCondition();
        } else {
            return false;
        }
    }

    function getDepositToken(address token, uint16 assetType) external view returns (address) {
        return _getDepsitToken(token, assetType);
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
            aavePool.getUserAccountData(_borrower);

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
        uint256 assetPrice = aavePriceGetter.getAssetPrice(_asset);

        address variableDebtToken = aavePool.getReserveVariableDebtToken(_asset);

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
        uint256 assetPrice = aavePriceGetter.getAssetPrice(_asset);

        address aToken = aavePool.getReserveAToken(_asset);

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
    {
        bytes32 marketId = morphoMarket[_market];
        if (marketId == bytes32(0)) {
            return false;
        }

        MarketParams memory market = morphoPool.idToMarketParams(Id.wrap(marketId));

        IOracle oracle = IOracle(market.oracle);

        uint256 price = oracle.price();

        Position memory position = morphoPool.position(Id.wrap(marketId), _borrower);

        Market memory marketData = morphoPool.market(Id.wrap(marketId));

        // Greater than asset Price
        if (_parameter == 0) {
            return conditionValue > price;
        } // Less than or equal to asset Price
        else if (_parameter == 1) {
            return conditionValue <= price;
        }

        return false;
    }

    function checkEulerCondition() public view returns (bool) {}

    function executeOrder(address vault, bytes32 _orderId, address _solver, IRouter.Route[] calldata route)
        external
        payable
    {
        // get params of the order
        (,,, uint32 destinationChainId,) = IVault(vault).decodeKey(abi.encodePacked(_orderId));

        // get Order details
        (address _owner, OrderExecutionDetails memory order) = IVault(vault).getOrderExecutionDetails(_orderId);

        // Execute the order
        IVault(vault).executeOrder{value: msg.value}(_orderId, _solver);

        if (destinationChainId == block.chainid) {
            address depositToken = _getDepsitToken(order.token, order.assetType);

            // transfer tokens
            IERC20(depositToken).transferFrom(vault, address(this), order.amount);

            // transform tokens
            uint256 amount = handleTransformation(order.token, order.assetType, order.amount);

            // swap tokens
            if (order.token != order.convert) {
                if (route.length == 0) {
                    revert InvalidRoute();
                }

                if (route[0].from != order.token) {
                    revert InvalidStartToken(order.token, route[0].from);
                }

                if (route[route.length - 1].to != order.convert) {
                    revert InvalidEndToken(order.convert, route[route.length - 1].to);
                }

                // Get First Pool for swap
                address pool = aerodromeRouter.poolFor(route[0].from, route[0].to, route[0].stable, route[0].factory);

                // Approve Call to Aerodrome Router
                IERC20(order.token).approve(pool, amount);

                // Swap Operation
                uint256[] memory output =
                    aerodromeRouter.swapExactTokensForTokens(amount, 0, route, address(this), block.timestamp);

                amount = output[output.length - 1];
            }

            // Deposit or Repay
            handleDeposit(order.convert, amount, _owner, order.platform, order.repay);
        }
    }

    function handleTransformation(address token, uint16 assetType, uint256 amount) internal returns (uint256) {
        if (assetType == 1) {
            // Calling Aave Pool withdraw function
            return aavePool.withdraw(token, amount, address(this));
        }

        return (amount);
    }

    function handleDeposit(address token, uint256 amount, address _owner, uint16 _platform, bool repay) internal {
        // Self Deposit
        if (_platform == 0) {
            IERC20(token).transfer(_owner, amount);
        }
        // Aave
        if (_platform == 1) {
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

        // Deposit into Morpho vaults
        if (_platform >= 2 && _platform <= 1002) {
            // TODO Deposits into vaults
        }

        //
        if (_platform >= 1003 && _platform <= 2003) {
            // TODO Supply collateral or repay loans in morpho
        }
    }

    function _getDepsitToken(address token, uint16 assetType) internal view returns (address) {
        if (assetType == 1) {
            return aavePool.getReserveAToken(token);
        }

        return token;
    }

    function convertToDepositAddress(uint16 input) public pure returns (address) {
        return address(uint160(uint256(input)));
    }
}
