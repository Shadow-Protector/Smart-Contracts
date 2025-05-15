// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

import {IAavePool} from "./interfaces/aave/IAavePool.sol";
import {IPriceOracleGetter} from "./interfaces/aave/IAavePriceGetter.sol";

import {IOracle} from "./interfaces/morpho/IMorphoOracle.sol";
import {IMorpho, MarketParams, Id, Position, Market} from "../src/interfaces/morpho/IMorpho.sol";
import {IMetaMorpho} from "./interfaces/morpho/IMetaMorpho.sol";

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
//   -> Euler Vault parameters
// -> Condition Value (type number) (uint256) (Stored inside the struct)
//   -> Asset Price Value in 18 decimals
//   -> Aave Values
//   -> Morpho Values
//   -> Euler Values

contract Handler {
    using MathLib for uint256;
    using SharesMathLib for uint256;

    address public owner;
    address public factory;
    address public usdc;
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
    mapping(uint32 => address) public crossChainHandlers;

    // Events
    event UpdatedOwner(address oldOwner, address newOwner);

    event MorphoMarketAdded(address market, bytes32 id);
    event MorphoVaultAdded(address vault, address vaultId);

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

    function updateFactory(address _factory) external onlyOwner {
        factory = _factory;
    }

    function updateUsdc(address _usdc) external onlyOwner {
        usdc = _usdc;
    }

    function addCrossChainHandler(uint32 _chainId, address _handler) external onlyOwner {
        crossChainHandlers[_chainId] = _handler;
    }

    function addMorphoMarket(address _market, bytes32 _id) external onlyOwner {
        morphoMarket[_market] = _id;
        emit MorphoMarketAdded(_market, _id);
    }

    function addMorphoVault(address _vault, address _vaultId) external onlyOwner {
        morphoVaults[_vault] = _vaultId;
        emit MorphoVaultAdded(_vault, _vaultId);
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
        uint256 priceWithTwoDecimals = getChainlinkData(_V3InterfaceAddress);

        // Greater than Value
        if (parameter == 0) {
            return priceWithTwoDecimals > conditionValue;
        }
        // Less than Value or equal to
        else if (parameter == 1) {
            return priceWithTwoDecimals <= conditionValue;
        }

        return false;
    }

    function checkAavePortfioCondition(address _borrower, uint16 _parameter, uint256 conditionValue)
        public
        view
        returns (bool)
    {
        // Overall Portfolio Value
        (uint256 totalCollateralBase, uint256 totalDebtBase, uint256 ltv, uint256 healthFactor) =
            getAavePortfolioData(_borrower);

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
        } // Check paramter is greater than ltv
        else if (_parameter == 4) {
            return ltv > conditionValue;
        } // Check paramter is less or equal to ltv
        else if (_parameter == 5) {
            return ltv <= conditionValue;
        } // Check parameter is greater than healthFactor
        else if (_parameter == 6) {
            return healthFactor > conditionValue;
        } // Check paramter is less or equal to healthFactor
        else if (_parameter == 7) {
            return healthFactor <= conditionValue;
        }

        return false;
    }

    function checkAaveDebtCondition(address _asset, address _borrower, uint16 _parameter, uint256 conditionValue)
        public
        view
        returns (bool)
    {
        (uint256 assetPrice, uint256 debtBalance, uint256 debtBalanceInBaseCurrency) =
            getAaveDebtData(_asset, _borrower);

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
        (uint256 assetPrice, uint256 collateralBalance, uint256 collateralBalanceInBaseCurrency) =
            getAaveCollateralData(_asset, _borrower);

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

        uint8 decimals = 34 + IERC20(market.loanToken).decimals() - IERC20(market.collateralToken).decimals();

        price = price / 10 ** decimals;

        uint256 borrowed =
            uint256(position.borrowShares).toAssetsUp(marketData.totalBorrowAssets, marketData.totalBorrowShares);

        // Greater than asset Price
        if (_parameter == 0) {
            return price > conditionValue;
        } // Less than or equal to asset Price
        else if (_parameter == 1) {
            return price <= conditionValue;
        } else if (_parameter == 2) {
            return borrowed > conditionValue;
        } // Less than or equal to debt balance
        else if (_parameter == 3) {
            return borrowed <= conditionValue;
        }

        return false;
    }

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

        // Withdraw from Morpho Vaults
        if (assetType >= 2 && assetType <= 1002) {
            address vaultAddress = morphoVaults[convertToDepositAddress(assetType)];
            return IMetaMorpho(vaultAddress).redeem(amount, address(this), address(this));
        }

        return (amount);
    }

    function handleDeposit(address token, uint256 amount, address _owner, uint16 _platform, bool repay) internal {
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
            address vaultAddress = morphoVaults[convertToDepositAddress(_platform)];
            if (vaultAddress == address(0)) {
                _platform = 0;
            } else {
                address confirmAsset = IMetaMorpho(vaultAddress).asset();

                if (token != confirmAsset) {
                    _platform = 0;
                } else {
                    IERC20(token).approve(vaultAddress, amount);
                    IMetaMorpho(vaultAddress).deposit(amount, _owner);
                }
            }
        }

        //
        if (_platform >= 1003 && _platform <= 2003) {
            // Supply collateral or repay loans in morpho Markets
            bytes32 marketId = morphoMarket[convertToDepositAddress(_platform)];

            if (marketId == bytes32(0)) {
                _platform = 0;
            } else {
                MarketParams memory market = morphoPool.idToMarketParams(Id.wrap(marketId));
                // Repay s
                if (repay && token == market.loanToken) {
                    Position memory position = morphoPool.position(Id.wrap(marketId), _owner);

                    Market memory marketData = morphoPool.market(Id.wrap(marketId));

                    uint256 borrowed = uint256(position.borrowShares).toAssetsUp(
                        marketData.totalBorrowAssets, marketData.totalBorrowShares
                    );

                    uint256 repayValue = amount;
                    if (amount > borrowed) {
                        repayValue = borrowed;
                        IERC20(token).transfer(_owner, amount - borrowed);
                    }

                    morphoPool.repay(
                        market,
                        repayValue, // Amount of assets to repay
                        0, // Use 0 for shares when specifying assets
                        address(owner), // Repay on behalf of this contract
                        "" // No callback data needed
                    );
                } else if (!repay && token == market.collateralToken) {
                    IERC20(token).approve(address(morphoPool), amount);
                    morphoPool.supplyCollateral(market, amount, _owner, "");
                } else {
                    _platform = 0;
                }
            }
        }

        // Self Deposit
        if (_platform == 0) {
            IERC20(token).transfer(_owner, amount);
        }
    }

    function executeCrossChainOrder(address vault, bytes32 _orderId, uint32 destinationChainId) external {
        require(msg.sender == factory, "Not Factory");

        // get Order details
        (address _owner, OrderExecutionDetails memory order) = IVault(vault).getOrderExecutionDetails(_orderId);

        // Get Deposit Token
        address depositToken = _getDepsitToken(order.token, order.assetType);

        // transfer tokens
        IERC20(depositToken).transferFrom(vault, address(this), order.amount);

        // transform tokens
        uint256 amount = handleTransformation(order.token, order.assetType, order.amount);

        // TODO: Cross Chain transfer

        IERC20(depositToken).transfer(_owner, amount);
    }

    function _getDepsitToken(address token, uint16 assetType) internal view returns (address) {
        if (assetType == 1) {
            return aavePool.getReserveAToken(token);
        }

        // Withdraw from Morpho Vaults
        if (assetType >= 2 && assetType <= 1002) {
            return morphoVaults[convertToDepositAddress(assetType)];
        }

        return token;
    }

    function convertToDepositAddress(uint16 input) public pure returns (address) {
        return address(uint160(uint256(input)));
    }

    function getChainlinkData(address _V3InterfaceAddress) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_V3InterfaceAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 priceValue = uint256(price);
        uint256 priceDecimals = 10 ** priceFeed.decimals();

        return ((priceValue * 100) / priceDecimals);
    }

    function getAavePortfolioData(address _borrower) public view returns (uint256, uint256, uint256, uint256) {
        (uint256 totalCollateralBase, uint256 totalDebtBase,,, uint256 ltv, uint256 healthFactor) =
            aavePool.getUserAccountData(_borrower);
        return (totalCollateralBase, totalDebtBase, ltv, healthFactor);
    }

    function getAaveDebtData(address _asset, address _borrower) public view returns (uint256, uint256, uint256) {
        uint256 assetUnit = 10 ** IERC20(_asset).decimals();
        uint256 assetPrice = aavePriceGetter.getAssetPrice(_asset);

        address variableDebtToken = aavePool.getReserveVariableDebtToken(_asset);

        uint256 debtBalance = IERC20(variableDebtToken).balanceOf(_borrower);

        uint256 debtBalanceInBaseCurrency = (debtBalance * assetPrice) / assetUnit;

        return (assetPrice, debtBalance, debtBalanceInBaseCurrency);
    }

    function getAaveCollateralData(address _asset, address _borrower) public view returns (uint256, uint256, uint256) {
        uint256 assetUnit = 10 ** IERC20(_asset).decimals();
        uint256 assetPrice = aavePriceGetter.getAssetPrice(_asset);

        address aToken = aavePool.getReserveAToken(_asset);

        uint256 collateralBalance = IERC20(aToken).balanceOf(_borrower);

        uint256 collateralBalanceInBaseCurrency = (collateralBalance * assetPrice) / assetUnit;

        return (assetPrice, collateralBalance, collateralBalanceInBaseCurrency);
    }
}
