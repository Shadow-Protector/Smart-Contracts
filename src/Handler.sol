// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

import {IAavePool} from "./interfaces/aave/IAavePool.sol";
import {IPriceOracleGetter} from "./interfaces/aave/IAavePriceGetter.sol";

import {ICCTP} from "./interfaces/circle/ICCTP.sol";
import {IMessageTransmitter} from "./interfaces/circle/IMessageTransmitter.sol";
import {IOracle} from "./interfaces/morpho/IMorphoOracle.sol";
import {IMorpho, MarketParams, Id, Position, Market} from "../src/interfaces/morpho/IMorpho.sol";
import {IMetaMorpho} from "./interfaces/morpho/IMetaMorpho.sol";

import {MathLib, WAD} from "./lib/MathLib.sol";
import {SharesMathLib} from "./lib/SharesMathLib.sol";

import {IRouter} from "./interfaces/aerodrome/IRouter.sol";

import {IVault, OrderExecutionDetails} from "./interfaces/IVault.sol";
import {IFactory, CrossChainData} from "./interfaces/IFactory.sol";
import {IHandler} from "./interfaces/IHandler.sol";

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

/// @title Handler
/// @author Shadow Protector, @parizval
/// @notice Handler Contract evaluates order conditon, interacts with Solvers for executing orders, swapping tokens, supplying or repaying assets to Aave, Morpho or User.
contract Handler is IHandler {
    using MathLib for uint256;
    using SharesMathLib for uint256;

    address public owner;
    address public factory;
    IAavePool public immutable aavePool;
    IPriceOracleGetter public immutable aavePriceGetter;
    uint8 public routeLength = 1;
    IMorpho public immutable morphoPool;

    // Aerodrome Router
    IRouter public immutable aerodromeRouter;

    address public immutable eulerPool;

    // Mappings
    mapping(address => bytes32) public morphoMarket;
    mapping(address => address) public morphoVaults;
    mapping(address => address) public eulerDepositVaults;
    mapping(bytes32 => address) private crossChainOrders;

    // Events
    event UpdatedOwner(address oldOwner, address newOwner);

    event MorphoMarketAdded(address market, bytes32 id);
    event MorphoVaultAdded(address vault, address vaultId);

    // Errors
    error NotOwner(address sender, address owner);
    error MorphoMarketNotFound(address marketKey);
    error InvalidRoute();
    error InvalidRouteLength(uint256 routeLength, uint8 requiredRouteLength);
    error InvalidStartToken(address requiredToken, address startToken);
    error InvalidEndToken(address requiredToken, address endToken);
    error InvalidMorphoVault(uint16 vaultId);
    error BaseTokenNotUSDC(address token, address usdc);
    error SenderNotMessageTransmitter(address sender, address messageTransmitter);

    constructor(address _aavePool, address _aavePriceGetter, address _morphoPool, address _aerodromeRouter) {
        owner = msg.sender;
        aavePool = IAavePool(_aavePool);
        aavePriceGetter = IPriceOracleGetter(_aavePriceGetter);
        morphoPool = IMorpho(_morphoPool);
        aerodromeRouter = IRouter(_aerodromeRouter);
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

    function updateFactory(address _factory) external OnlyOwner {
        factory = _factory;
    }

    function updateRouteLength(uint8 _routeLength) external OnlyOwner {
        routeLength = _routeLength;
    }

    function addMorphoMarket(address _market, bytes32 _marketId) external OnlyOwner {
        morphoMarket[_market] = _marketId;
        emit MorphoMarketAdded(_market, _marketId);
    }

    function addMorphoVault(address _vaultId, address _vaultAddress) external OnlyOwner {
        morphoVaults[_vaultId] = _vaultAddress;
        emit MorphoVaultAdded(_vaultId, _vaultAddress);
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
        return _getDepositToken(token, assetType);
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

        uint256 priceWithTwoDecimals = ((priceValue * 100) / priceDecimals);

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

    function checkMorphoCondition(address _market, address _borrower, uint16 _parameter, uint256 conditionValue)
        public
        view
        returns (bool)
    {
        bytes32 marketId = morphoMarket[_market];
        if (marketId == bytes32(0)) {
            revert MorphoMarketNotFound(_market);
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
        (,,, uint32 destinationChainId) = IVault(vault).decodeKey(abi.encodePacked(_orderId));

        // get Order details
        (address _owner, OrderExecutionDetails memory order) = IVault(vault).getOrderExecutionDetails(_orderId);

        // Execute the order
        IVault(vault).executeOrder{value: msg.value}(_orderId, _solver);

        if (destinationChainId == block.chainid) {
            address depositToken = _getDepositToken(order.token, order.assetType);

            // transfer tokens
            IERC20(depositToken).transferFrom(vault, address(this), order.amount);

            // transform tokens
            uint256 amount = handleTransformation(order.token, order.assetType, order.amount);

            // swap tokens
            if (order.token != order.convert) {
                amount = swap(amount, route, order.token, order.convert);
            }

            // Deposit or Repay
            handleDeposit(order.convert, amount, _owner, order.platform, order.repay);
        } else {
            crossChainOrders[_orderId] = _solver;
        }
    }

    function executeCrossChainOrder(
        bytes calldata message,
        bytes calldata attestation,
        address _solver,
        IRouter.Route[] calldata route
    ) public {
        (address messageTransmitter, address usdc) = IFactory(factory).getMessageTransmitter();

        // Call Token Minter to get the USDC and store the hook Data
        IMessageTransmitter(messageTransmitter).receiveMessage(message, attestation);

        // Storing messageTransmitter
        assembly {
            tstore(0x00, messageTransmitter)
        }

        // Fetching Variables for storage
        bytes32 orderId;
        address vaultOwner;
        address convertToken;
        uint16 platform;
        bool repay;

        assembly {
            orderId := tload(0x00)
            vaultOwner := tload(0x01)
            convertToken := tload(0x03)
            platform := tload(0x04)
            repay := tload(0x05)
        }

        address storedSolver = crossChainOrders[orderId];
        if (storedSolver != _solver) {
            storedSolver = owner;
        }

        uint256 amount = IERC20(usdc).balanceOf(address(this));

        // Executing Operation
        if (convertToken != usdc) {
            // Executing Swap
            amount = swap(amount, route, usdc, convertToken);
        }

        // Handling Convert Token
        handleDeposit(convertToken, amount, owner, platform, repay);

        // Request Tip After Order Execution
        IFactory(factory).getTipForCrossChainOrder(orderId, owner, storedSolver);

        delete crossChainOrders[orderId];
    }

    function handleCrossChainUSDC(
        bytes32 _orderId,
        address _vaultOwner,
        address _convert,
        uint16 _platform,
        bool _repay
    ) external {
        address messageTransmitter;
        assembly {
            messageTransmitter := tload(0x00)
        }

        // Ensure Minter Call
        if (msg.sender != messageTransmitter) {
            revert SenderNotMessageTransmitter(msg.sender, messageTransmitter);
        }

        // Storing Execution Order Data
        assembly {
            tstore(0x01, _orderId)
            tstore(0x02, _vaultOwner)
            tstore(0x03, _convert)
            tstore(0x04, _platform)
            tstore(0x05, _repay)
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
                revert InvalidMorphoVault(_platform);
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
        address depositToken = _getDepositToken(order.token, order.assetType);

        // transfer tokens
        IERC20(depositToken).transferFrom(vault, address(this), order.amount);

        // transform tokens
        uint256 amount = handleTransformation(order.token, order.assetType, order.amount);

        // TODO: Cross Chain transfer
        IERC20(depositToken).transfer(_owner, amount);

        // Get Cross Chain Data
        (address usdc, address tokenMessenger, CrossChainData memory crossChainData) =
            IFactory(factory).getCrossChainData(destinationChainId);

        // Check that the base token is USDC
        if (order.token != usdc) {
            // Return Error
            revert BaseTokenNotUSDC(order.token, usdc);
        }

        // Approve Call to Token Messenger
        IERC20(usdc).approve(tokenMessenger, amount);

        // bytes32 orderId -> 32 bytes
        // address Owner -> 20 bytes
        // Convert Token -> 20 bytes
        // uint16 platform -> 2 bytes
        // bool repay -> 1 byte
        bytes memory callData = abi.encodeWithSignature(
            "handleCrossChainUSDC(bytes32 _orderId, address _vaultOwner, address _convert, uint16 _platform, bool _repay)",
            _orderId,
            _owner,
            order.convert,
            order.platform,
            order.repay
        );

        bytes memory hookData = abi.encode(crossChainData.handler, callData);

        // Calling Token Messenger to bridge tokens along with the order details
        ICCTP(tokenMessenger).depositForBurnWithHook(
            amount,
            crossChainData.destinationDomain,
            addressToBytes32(crossChainData.handler), // mintRecipient
            usdc,
            addressToBytes32(crossChainData.handler),
            0,
            1000,
            hookData
        );

        IFactory(factory).emitCrossChainHook(_orderId);
    }

    function _getDepositToken(address token, uint16 assetType) internal view returns (address) {
        if (assetType == 1) {
            return aavePool.getReserveAToken(token);
        }

        // Withdraw from Morpho Vaults
        if (assetType >= 2 && assetType <= 1002) {
            return morphoVaults[convertToDepositAddress(assetType)];
        }

        return token;
    }

    function swap(uint256 amount, IRouter.Route[] calldata route, address startToken, address endToken)
        internal
        returns (uint256)
    {
        if (route.length == 0) {
            revert InvalidRoute();
        }

        if (route.length > routeLength) {
            revert InvalidRouteLength(route.length, routeLength);
        }

        if (route[0].from != startToken) {
            revert InvalidStartToken(startToken, route[0].from);
        }

        if (route[route.length - 1].to != endToken) {
            revert InvalidEndToken(endToken, route[route.length - 1].to);
        }

        // Approve Call to Aerodrome Router
        IERC20(startToken).approve(address(aerodromeRouter), amount);

        // Get Swap Output
        uint256[] memory amounts = aerodromeRouter.getAmountsOut(amount, route);

        // Swap Operation
        uint256[] memory output = aerodromeRouter.swapExactTokensForTokens(
            amount, amounts[amounts.length - 1], route, address(this), block.timestamp
        );

        amount = output[output.length - 1];

        return amount;
    }

    function convertToDepositAddress(uint16 input) public pure returns (address) {
        return address(uint160(uint256(input)));
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
