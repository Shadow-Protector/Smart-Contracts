// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

import {ICCTP} from "./interfaces/circle/ICCTP.sol";
import {IMessageTransmitter} from "./interfaces/circle/IMessageTransmitter.sol";

import {IRouter} from "./interfaces/aerodrome/IRouter.sol";

import {IVault, OrderExecutionDetails} from "./interfaces/IVault.sol";
import {IFactory, CrossChainData} from "./interfaces/IFactory.sol";
import {IHandler} from "./interfaces/IHandler.sol";
import {IActionHandler} from "./interfaces/IActionHandler.sol";

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
    address public owner;
    address public factory;
    uint8 public routeLength = 1;

    // Aerodrome Router
    IRouter public immutable aerodromeRouter;

    // Mappings

    // Platform Id => Condition Evaulation Address
    mapping(uint16 => address) public conditionPlatforms;

    // Platform Id => Action Platform Address
    mapping(uint16 => address) public actions;

    // OrderId => Solver Payout Address
    mapping(bytes32 => address) private crossChainOrders;

    // Events
    event UpdatedOwner(address oldOwner, address newOwner);
    event ConditionPlatformAdded(uint16 platformId, address platformAddress);
    event ActionPlatformAdded(uint16 platformId, address platformAddress);

    // Errors
    error NotOwner(address sender, address owner);
    error ActionAddressNotFound(uint16 assetType);
    error InvalidRoute();
    error InvalidRouteLength(uint256 routeLength, uint8 requiredRouteLength);
    error InvalidStartToken(address requiredToken, address startToken);
    error InvalidEndToken(address requiredToken, address endToken);
    error BaseTokenNotUSDC(address token, address usdc);
    error SenderNotMessageTransmitter(address sender, address messageTransmitter);

    constructor(address _aerodromeRouter) {
        owner = msg.sender;
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

    function addConditionPlatform(uint16 platformId, address platformAddress) external OnlyOwner {
        conditionPlatforms[platformId] = platformAddress;
        emit ConditionPlatformAdded(platformId, platformAddress);
    }

    function addActionPlatform(uint16 platformId, address actionPlatformAddress) external OnlyOwner {
        actions[platformId] = actionPlatformAddress;
        emit ActionPlatformAdded(platformId, actionPlatformAddress);
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
        } else {
            address platformAddressContract = conditionPlatforms[_platform];
            return IActionHandler(platformAddressContract).evaluateCondition(
                _platform, _platformAddress, _borrower, _parameter, _conditionValue
            );
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

    function getDepositToken(address token, uint16 assetType) external view returns (address) {
        return _getDepositToken(token, assetType);
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
            address depositToken = _getDepositToken(order.baseToken, order.assetType);

            // transfer tokens
            IERC20(depositToken).transferFrom(vault, address(this), order.amount);

            // transform tokens
            uint256 amount = handleTransformation(depositToken, order.baseToken, order.assetType, order.amount);

            // swap tokens
            if (order.baseToken != order.outputToken) {
                amount = swap(amount, route, order.baseToken, order.outputToken);
            }

            // Deposit or Repay
            handleDeposit(order.outputToken, amount, _owner, order.platform, order.repay);
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

    function handleTransformation(address depositToken, address baseToken, uint16 assetType, uint256 amount)
        internal
        returns (uint256)
    {
        if (depositToken == baseToken) {
            return amount;
        }

        address actionAddress = actions[assetType];

        if (actionAddress == address(0)) {
            actionAddress = actions[assetType / 1000];
        }

        if (actionAddress == address(0)) {
            revert ActionAddressNotFound(assetType);
        }

        // Approve Call for Unwinding Poisition
        IERC20(depositToken).approve(actionAddress, amount);

        // Calling Action Handler for Unwing Position
        return IActionHandler(actionAddress).unWindPosition(depositToken, baseToken, assetType, amount, address(this));
    }

    function handleDeposit(address token, uint256 amount, address _owner, uint16 _platform, bool repay) internal {
        // Self Deposit
        if (_platform == 0) {
            IERC20(token).transfer(_owner, amount);
        }

        address actionAddress = actions[_platform];

        if (actionAddress == address(0)) {
            actionAddress = actions[_platform / 1000];
        }

        if (actionAddress == address(0)) {
            revert ActionAddressNotFound(_platform);
        }

        // Adding Approve Call
        IERC20(token).approve(actionAddress, amount);

        IActionHandler(actionAddress).handleDeposit(token, amount, _owner, repay, _platform);
    }

    function executeCrossChainOrder(address vault, bytes32 _orderId, uint32 destinationChainId) external {
        require(msg.sender == factory, "Not Factory");

        // get Order details
        (address _owner, OrderExecutionDetails memory order) = IVault(vault).getOrderExecutionDetails(_orderId);

        // Get Deposit Token
        address depositToken = _getDepositToken(order.baseToken, order.assetType);

        // transfer tokens
        IERC20(depositToken).transferFrom(vault, address(this), order.amount);

        // transform tokens
        uint256 amount = handleTransformation(depositToken, order.baseToken, order.assetType, order.amount);

        // TODO: Cross Chain transfer
        IERC20(depositToken).transfer(_owner, amount);

        // Get Cross Chain Data
        (address usdc, address tokenMessenger, CrossChainData memory crossChainData) =
            IFactory(factory).getCrossChainData(destinationChainId);

        // Check that the base token is USDC
        if (order.baseToken != usdc) {
            // Return Error
            revert BaseTokenNotUSDC(order.baseToken, usdc);
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
            order.outputToken,
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

        IFactory(factory).emitCrossChainHook(vault, _orderId, destinationChainId);
    }

    function _getDepositToken(address token, uint16 assetType) internal view returns (address) {
        if (assetType == 0) {
            return token;
        }

        address actionAddress = actions[assetType];

        if (actionAddress == address(0)) {
            actionAddress = actions[assetType / 1000];
        }

        if (actionAddress == address(0)) {
            revert ActionAddressNotFound(assetType);
        }

        return IActionHandler(actionAddress).getDepositToken(token, assetType);
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
