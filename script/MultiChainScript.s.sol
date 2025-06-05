// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {HelperConfig} from "./HelperConfig.s.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";
import {IRouter} from "../src/interfaces/aerodrome/IRouter.sol";

import {Handler} from "../src/Handler.sol";
import {VaultFactory} from "../src/Factory.sol";
import {Vault} from "../src/Vault.sol";
import {VaultDeployer} from "../src/Deployer.sol";

contract DeployScript is Script {
    uint256 constant DECIMAL = 10 ** 6;

    address constant CHAINLINK_PRICE_FEED = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;

    HelperConfig.NetworkConfig baseConfig;
    Handler baseHandler;
    VaultFactory baseFactory;
    VaultDeployer baseVaultDeployer;
    address payable baseVault;

    HelperConfig.NetworkConfig ethConfig;
    Handler ethHandler;
    VaultFactory ethFactory;
    VaultDeployer ethVaultDeployer;
    address payable ethVault;

    function setUp() public {
        HelperConfig helperconfig = new HelperConfig();

        uint256 baseSepoliaFork = vm.createFork(vm.rpcUrl("base_sepolia"));

        uint256 ethSepoliaFork = vm.createFork(vm.rpcUrl("eth_sepolia"));

        vm.selectFork(baseSepoliaFork);

        vm.startBroadcast();

        baseConfig = helperconfig.getConfig();

        // Deploy the Handler contract
        baseHandler = new Handler(address(0), address(0), address(0), address(0));

        console.log("Base Handler Deployed at:", address(baseHandler));

        baseFactory = new VaultFactory(address(baseHandler), 0);

        console.log("Factory Deployed at:", address(baseFactory));

        baseHandler.updateFactory(address(baseFactory));

        baseVaultDeployer = new VaultDeployer(address(baseFactory), baseConfig.hyperlaneMailboxAddress);

        console.log("Base Vault Deployer Deployed at:", address(baseVaultDeployer));

        baseFactory.updateVaultDeployer(address(baseVaultDeployer));

        baseVault = payable(baseVaultDeployer.deployVault());

        console.log("Base Vault deployed at:", baseVault);

        vm.stopBroadcast();

        // Deploying Contracts on Eth Sepolia

        vm.selectFork(ethSepoliaFork);

        vm.startBroadcast();

        ethConfig = helperconfig.getConfig();

        ethHandler = new Handler(address(0), address(0), address(0), address(0));

        console.log("ETH Handler Deployed at:", address(ethHandler));

        ethFactory = new VaultFactory(address(ethHandler), 0);

        console.log("ETH Factory Deployed at:", address(ethFactory));

        ethHandler.updateFactory(address(ethFactory));

        ethVaultDeployer = new VaultDeployer(address(ethFactory), ethConfig.hyperlaneMailboxAddress);

        console.log("ETH Vault Deployer Deployed at:", address(ethVaultDeployer));

        ethFactory.updateVaultDeployer(address(ethVaultDeployer));

        ethVault = payable(ethVaultDeployer.deployVault());

        console.log("ETH Vault deployed at:", ethVault);

        Vault(ethVault).addExternalChainVault(84532, baseVault);

        vm.stopBroadcast();

        vm.selectFork(baseSepoliaFork);

        vm.startBroadcast();

        Vault(baseVault).addExternalChainVault(11155111, ethVault);

        vm.stopBroadcast();
    }

    function run() public {
        simulationScript();
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
            return PriceWithTwoDecimals > conditionValue;
        }
        // Less than Value or equal to
        else if (parameter == 1) {
            return PriceWithTwoDecimals <= conditionValue;
        }

        return false;
    }

    function simulationScript() public {

        uint256 baseSepoliaFork = vm.createFork(vm.rpcUrl("base_sepolia"));

        uint256 ethSepoliaFork = vm.createFork(vm.rpcUrl("eth_sepolia"));

        vm.selectFork(baseSepoliaFork);

        vm.startBroadcast();

        uint256 base_initialBalance = IERC20(baseConfig.usdcAddress).balanceOf(msg.sender);

        console.log("Base Initial Balance:", base_initialBalance);

        IERC20(baseConfig.usdcAddress).approve(address(baseVault), 2 * DECIMAL);

        Vault(baseVault).createOrder(
            0, CHAINLINK_PRICE_FEED, 0, 11155111, 0, 241164, address(baseConfig.usdcAddress), 2 * DECIMAL
        );

        bytes32 orderId = Vault(baseVault).generateKey(0, CHAINLINK_PRICE_FEED, 0, 11155111, 0);

        console.log("Check Conditon Bool:", checkChainlinkCondition(CHAINLINK_PRICE_FEED, 0, 241164));

        vm.stopBroadcast();

        vm.selectFork(ethSepoliaFork);

        vm.startBroadcast();

        IERC20(ethConfig.usdcAddress).approve(address(ethVault), 5 * DECIMAL);

        Vault(ethVault).depositAsset(orderId, ethConfig.usdcAddress, 0, ethConfig.usdcAddress, 5 * DECIMAL, 0, false);

        vm.stopBroadcast();

        vm.selectFork(baseSepoliaFork);

        vm.startBroadcast();

        address(baseVault).call{value: 0.3 ether}("");

        // Vault(base_vault).cancelOrder(orderId);

        // assert(base_factory.checkCondition(0, CHAINLINK_PRICE_FEED, msg.sender, 0, 271164) == true);

        IRouter.Route[] memory routes = new IRouter.Route[](0);

        baseHandler.executeOrder(address(baseVault), orderId, 0xA01f6403d49857b58D3794C12E028c3681b24F98, routes);

        vm.stopBroadcast();

        // CONSTANTS

        // Starting Simulation

        // deployer.deployVault();

        // uint256 initialBalance = IERC20(USDC).balanceOf(msg.sender);

        // console.log("Initial Balance:", initialBalance);

        // IERC20(USDC).approve(address(vault), 12 * decimal);

        // vault.createOrder(0, CHAINLINK_PRICE_FEED, 0, uint32(block.chainid), 0, 261164, address(USDC), 2 * decimal);

        // bytes32 orderId = vault.generateKey(0, CHAINLINK_PRICE_FEED, 0, uint32(block.chainid), 0);

        // // Order Creation Checks

        // assert(IERC20(USDC).balanceOf(msg.sender) == initialBalance - 2 * decimal);

        // assert(IERC20(USDC).balanceOf(address(vault)) == 2 * decimal);

        // // Depsosit
        // vault.depositAsset(orderId, USDC, 0, USDC, 10 * decimal, 1, false);

        // // Deposit Checks
        // assert(IERC20(USDC).balanceOf(address(vault)) == 12 * decimal);
        // assert(IERC20(USDC).balanceOf(msg.sender) == initialBalance - 12 * decimal);

        // // Execute Order

        // // assert(handler.evaluateCondition(0, CHAINLINK_PRICE_FEED, msg.sender, 0, 251164) == true);

        // // assert(factory.checkCondition(0, CHAINLINK_PRICE_FEED, msg.sender, 0, 251164) == true);

        // handler.executeOrder(address(vault), orderId, 0xA01f6403d49857b58D3794C12E028c3681b24F98, routes);
    }
}
