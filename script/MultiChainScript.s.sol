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

    function setUp() public {}

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

    function simulationScript() public {
        HelperConfig helperconfig = new HelperConfig();

        uint256 baseSepoliaFork = vm.createFork(vm.rpcUrl("base_sepolia"));

        uint256 ethSepoliaFork = vm.createFork(vm.rpcUrl("eth_sepolia"));

        vm.selectFork(baseSepoliaFork);

        vm.startBroadcast();

        HelperConfig.NetworkConfig memory base_config = helperconfig.getConfig();

        // Deploy the Handler contract
        Handler base_handler = new Handler(address(0), address(0), address(0), address(0));

        console.log("Base Handler Deployed at:", address(base_handler));

        VaultFactory base_factory = new VaultFactory(address(base_handler), 0);

        console.log("Factory Deployed at:", address(base_factory));

        base_handler.updateFactory(address(base_factory));

        VaultDeployer base_deployer = new VaultDeployer(address(base_factory), base_config.hyperlaneMailboxAddress);

        console.log("Base Vault Deployer Deployed at:", address(base_deployer));

        base_factory.updateVaultDeployer(address(base_deployer));

        address payable base_vault = payable(base_deployer.deployVault());

        console.log("Base Vault deployed at:", base_vault);

        vm.stopBroadcast();

        // Deploying Vaults on Eth Sepolia

        vm.selectFork(ethSepoliaFork);

        vm.startBroadcast();

        HelperConfig.NetworkConfig memory eth_config = helperconfig.getConfig();

        Handler eth_handler = new Handler(address(0), address(0), address(0), address(0));

        console.log("ETH Handler Deployed at:", address(eth_handler));

        VaultFactory eth_factory = new VaultFactory(address(eth_handler), 0);

        console.log("ETH Factory Deployed at:", address(eth_factory));

        eth_handler.updateFactory(address(eth_factory));

        VaultDeployer eth_deployer = new VaultDeployer(address(eth_factory), eth_config.hyperlaneMailboxAddress);

        console.log("ETH Vault Deployer Deployed at:", address(eth_deployer));

        eth_factory.updateVaultDeployer(address(eth_deployer));

        address payable eth_vault = payable(eth_deployer.deployVault());

        console.log("ETH Vault deployed at:", eth_vault);

        // Connecting Vaults

        Vault(eth_vault).addExternalChainVault(84532, base_vault);

        uint256 eth_initialBalance = IERC20(eth_config.usdcAddress).balanceOf(msg.sender);

        console.log("ETH Initial Balance:", eth_initialBalance);

        vm.stopBroadcast();

        vm.selectFork(baseSepoliaFork);

        vm.startBroadcast();

        Vault(base_vault).addExternalChainVault(11155111, eth_vault);

        uint256 base_initialBalance = IERC20(base_config.usdcAddress).balanceOf(msg.sender);

        console.log("Base Initial Balance:", base_initialBalance);

        IERC20(base_config.usdcAddress).approve(address(base_vault), 2 * DECIMAL);

        Vault(base_vault).createOrder(
            0, CHAINLINK_PRICE_FEED, 0, 11155111, 0, 271164, address(base_config.usdcAddress), 2 * DECIMAL
        );

        bytes32 orderId = Vault(base_vault).generateKey(0, CHAINLINK_PRICE_FEED, 0, 11155111, 0);

        vm.stopBroadcast();

        vm.selectFork(ethSepoliaFork);

        vm.startBroadcast();

        IERC20(eth_config.usdcAddress).approve(address(eth_vault), 5 * DECIMAL);

        Vault(eth_vault).depositAsset(orderId, eth_config.usdcAddress, 0, eth_config.usdcAddress, 5 * DECIMAL, 0, false);

        vm.stopBroadcast();

        vm.selectFork(baseSepoliaFork);

        vm.startBroadcast();

        address(base_vault).call{value: 0.3 ether}("");

        // Vault(base_vault).cancelOrder(orderId);

        assert(base_factory.checkCondition(0, CHAINLINK_PRICE_FEED, msg.sender, 0, 271164) == true);

        IRouter.Route[] memory routes = new IRouter.Route[](0);

        base_handler.executeOrder(address(base_vault), orderId, 0xA01f6403d49857b58D3794C12E028c3681b24F98, routes);

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
