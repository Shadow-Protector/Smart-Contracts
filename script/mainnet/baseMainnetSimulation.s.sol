// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";
import {IRouter} from "../../src/interfaces/aerodrome/IRouter.sol";

import {Handler} from "../../src/Handler.sol";
import {VaultFactory} from "../../src/Factory.sol";
import {Vault} from "../../src/Vault.sol";
import {VaultDeployer} from "../../src/Deployer.sol";

contract DeployScript is Script {
    address constant CHAINLINK_PRICE_FEED = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;

    address constant AavePool = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;

    address constant AavePriceGetter = 0x2Cc0Fc26eD4563A5ce5e8bdcfe1A2878676Ae156;

    address constant MorphoPool = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    address constant AerodromeRouter = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;

    address constant HyperlaneMailbox = 0xeA87ae93Fa0019a82A727bfd3eBd1cFCa8f64f1D;

    Vault vault;
    Handler handler;
    VaultFactory factory;
    VaultDeployer deployer;

    function setUp() public {
        handler = Handler(0xdE8bb0fbcA6deE981c607C54f94bdd34A9D15362);
        factory = VaultFactory(0xEc9A1021cC0d4619ac6405a648239bEB0bFCf76C);
        vault = Vault(payable(0x2554823F28f819a6D75081Ec65f7Be1798447eBD));
        deployer = VaultDeployer(0xbF7d635B1F6fed745d9414a414F1f8B372C0bd79);
    }

    function run() public {
        depositIntoMorpho();
        // SwapAndRecieve();
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

        console.log("PriceWithTwoDecimals:", PriceWithTwoDecimals);

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

    function depositIntoAave() public {
        uint256 base_mainnet = vm.createFork(vm.rpcUrl("base_mainnet"));

        vm.selectFork(base_mainnet);

        vm.startBroadcast();

        // CONSTANTS

        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        uint256 decimal = 10 ** 5;

        // address CHAINLINK_PRICE_FEED = 0xd7818272B9e248357d13057AAb0B417aF31E817d;

        // Starting Simulation

        uint256 initialBalance = IERC20(USDC).balanceOf(msg.sender);

        console.log("Initial Balance:", initialBalance);

        IERC20(USDC).approve(address(vault), 10 * decimal);

        vault.createOrder(0, CHAINLINK_PRICE_FEED, 0, uint32(block.chainid), 0, 201164, address(USDC), 5 * decimal);

        bytes32 orderId = vault.generateKey(0, CHAINLINK_PRICE_FEED, 0, uint32(block.chainid), 0);

        checkChainlinkCondition(CHAINLINK_PRICE_FEED, 0, 201164);

        // // Order Creation Checks

        assert(IERC20(USDC).balanceOf(msg.sender) == initialBalance - 5 * decimal);

        assert(IERC20(USDC).balanceOf(address(vault)) == 5 * decimal);

        // // Depsosit
        vault.depositAsset(orderId, USDC, 0, USDC, 5 * decimal, 1, false);

        // // Deposit Checks
        assert(IERC20(USDC).balanceOf(address(vault)) == 10 * decimal);
        assert(IERC20(USDC).balanceOf(msg.sender) == initialBalance - 10 * decimal);

        // // Execute Order

        assert(handler.evaluateCondition(0, CHAINLINK_PRICE_FEED, msg.sender, 0, 201164) == true);

        assert(factory.checkCondition(0, CHAINLINK_PRICE_FEED, msg.sender, 0, 201164) == true);

        IRouter.Route[] memory routes = new IRouter.Route[](0);

        handler.executeOrder(address(vault), orderId, 0xA01f6403d49857b58D3794C12E028c3681b24F98, routes);

        vm.stopBroadcast();
    }

    function depositIntoMorpho() public {
        uint256 base_mainnet = vm.createFork(vm.rpcUrl("base_mainnet"));

        vm.selectFork(base_mainnet);

        vm.startBroadcast();

        // CONSTANTS

        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        uint256 decimal = 10 ** 6;

        address AERO_PRICE_FEED = 0x4EC5970fC728C5f65ba413992CD5fF6FD70fcfF0;

        // Starting Simulation

        uint256 initialBalance = IERC20(USDC).balanceOf(msg.sender);

        console.log("Initial Balance:", initialBalance);

        IERC20(USDC).approve(address(vault), 2 * decimal);

        vault.createOrder(0, AERO_PRICE_FEED, 0, uint32(block.chainid), 2, 50, address(USDC), 100);

        bytes32 orderId = vault.generateKey(0, AERO_PRICE_FEED, 0, uint32(block.chainid), 2);

        checkChainlinkCondition(AERO_PRICE_FEED, 0, 50);

        // // Order Creation Checks

        assert(IERC20(USDC).balanceOf(msg.sender) == initialBalance - 100);

        assert(IERC20(USDC).balanceOf(address(vault)) == 100);

        // // // Depsosit
        vault.depositAsset(orderId, USDC, 0, USDC, 1 * decimal, 3, false);

        // // // Deposit Checks
        assert(IERC20(USDC).balanceOf(address(vault)) == 1 * decimal + 100);
        assert(IERC20(USDC).balanceOf(msg.sender) == initialBalance - 1 * decimal - 100);

        // // // Execute Order

        assert(handler.evaluateCondition(0, AERO_PRICE_FEED, msg.sender, 0, 50) == true);

        assert(factory.checkCondition(0, AERO_PRICE_FEED, msg.sender, 0, 50) == true);

        IRouter.Route[] memory routes = new IRouter.Route[](0);

        address vaultId = handler.convertToDepositAddress(3);

        handler.executeOrder(address(vault), orderId, 0xA01f6403d49857b58D3794C12E028c3681b24F98, routes);

        vm.stopBroadcast();
    }

    function SwapAndRecieve() public {
        uint256 base_mainnet = vm.createFork(vm.rpcUrl("base_mainnet"));

        vm.selectFork(base_mainnet);

        vm.startBroadcast();

        // CONSTANTS

        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
        uint256 decimal = 10 ** 6;

        address AERO_PRICE_FEED = 0x4EC5970fC728C5f65ba413992CD5fF6FD70fcfF0;

        // Starting Simulation

        uint256 initialBalance = IERC20(USDC).balanceOf(msg.sender);

        console.log("Initial Balance:", initialBalance);

        IERC20(USDC).approve(address(vault), 2 * decimal);

        vault.createOrder(0, AERO_PRICE_FEED, 0, uint32(block.chainid), 0, 50, address(USDC), 100);

        bytes32 orderId = vault.generateKey(0, AERO_PRICE_FEED, 0, uint32(block.chainid), 0);

        checkChainlinkCondition(AERO_PRICE_FEED, 0, 1);

        // // Order Creation Checks

        assert(IERC20(USDC).balanceOf(msg.sender) == initialBalance - 100);

        assert(IERC20(USDC).balanceOf(address(vault)) == 100);

        // // // Depsosit
        vault.depositAsset(orderId, USDC, 0, AERO, 1 * decimal, 0, false);

        // // // Deposit Checks
        assert(IERC20(USDC).balanceOf(address(vault)) == 1 * decimal + 100);
        assert(IERC20(USDC).balanceOf(msg.sender) == initialBalance - 1 * decimal - 100);

        // // // Execute Order

        assert(handler.evaluateCondition(0, AERO_PRICE_FEED, msg.sender, 0, 50) == true);

        assert(factory.checkCondition(0, AERO_PRICE_FEED, msg.sender, 0, 50) == true);

        Handler newHandler = new Handler(AerodromeRouter);
        console.log("New Handler Deployed at:", address(newHandler));

        factory.updateHandler(address(newHandler));

        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] =
            IRouter.Route({from: USDC, to: AERO, stable: false, factory: 0x420DD381b31aEf6683db6B902084cB0FFECe40Da});

        newHandler.executeOrder(address(vault), orderId, 0xA01f6403d49857b58D3794C12E028c3681b24F98, routes);

        vm.stopBroadcast();
    }
}
