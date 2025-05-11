// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";
import {IRouter} from "../src/interfaces/aerodrome/IRouter.sol";

import {Handler} from "../src/Handler.sol";
import {VaultFactory} from "../src/Factory.sol";
import {Vault} from "../src/Vault.sol";
import {VaultDeployer} from "../src/Deployer.sol";

contract DeployScript is Script {
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
        uint256 baseSepoliaFork = vm.createFork(vm.rpcUrl("base_sepolia"));

        vm.selectFork(baseSepoliaFork);

        vm.startBroadcast();

        // Deploy the Handler contract
        Handler handler = new Handler(address(0), address(0), address(0), address(0));

        console.log("Handeler Deployed at:", address(handler));

        VaultFactory factory = new VaultFactory(address(handler), 0);

        console.log("Factory Deployed at:", address(factory));

        Vault vault = new Vault(msg.sender, address(factory), address(0));

        console.log("Vault Deployed at:", address(vault));

        VaultDeployer deployer = new VaultDeployer(address(factory), address(0));

        factory.updateVaultDeployer(address(deployer));

        // CONSTANTS

        address USDC = 0x036CbD53842c5426634e7929541eC2318f3dCF7e;
        uint256 decimal = 10 ** 6;

        address CHAINLINK_PRICE_FEED = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;

        // Starting Simulation

        deployer.deployVault();

        uint256 initialBalance = IERC20(USDC).balanceOf(msg.sender);

        console.log("Initial Balance:", initialBalance);

        IERC20(USDC).approve(address(vault), 12 * decimal);

        vault.createOrder(0, CHAINLINK_PRICE_FEED, 0, uint32(block.chainid), 0, 261164, address(USDC), 2 * decimal);

        bytes32 orderId = vault.generateKey(0, CHAINLINK_PRICE_FEED, 0, uint32(block.chainid), 0);

        // Order Creation Checks

        assert(IERC20(USDC).balanceOf(msg.sender) == initialBalance - 2 * decimal);

        assert(IERC20(USDC).balanceOf(address(vault)) == 2 * decimal);

        // Depsosit
        vault.depositAsset(orderId, USDC, 0, USDC, 10 * decimal, 1, false);

        // Deposit Checks
        assert(IERC20(USDC).balanceOf(address(vault)) == 12 * decimal);
        assert(IERC20(USDC).balanceOf(msg.sender) == initialBalance - 12 * decimal);

        // Execute Order

        // assert(handler.evaluateCondition(0, CHAINLINK_PRICE_FEED, msg.sender, 0, 251164) == true);

        // assert(factory.checkCondition(0, CHAINLINK_PRICE_FEED, msg.sender, 0, 251164) == true);

        IRouter.Route[] memory routes = new IRouter.Route[](0);

        handler.executeOrder(address(vault), orderId, 0xA01f6403d49857b58D3794C12E028c3681b24F98, routes);

        vm.stopBroadcast();
    }
}
