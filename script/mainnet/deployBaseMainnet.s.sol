// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";
import {IRouter} from "../../src/interfaces/aerodrome/IRouter.sol";

import {VaultFactory} from "../../src/Factory.sol";
import {Vault} from "../../src/Vault.sol";
import {VaultDeployer} from "../../src/Deployer.sol";
import {Handler} from "../../src/Handler.sol";

import {AaveHandler} from "../../src/Actions/AaveHandler.sol";
import {MorphoHandler} from "../../src/Actions/MorphoHandler.sol";


contract DeployScript is Script {
    address constant CHAINLINK_PRICE_FEED = 0x4aDC67696bA383F43DD60A9e78F2C97Fbbfc7cb1;

    address constant AavePool = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5;

    address constant AavePriceGetter = 0x2Cc0Fc26eD4563A5ce5e8bdcfe1A2878676Ae156;

    address constant MorphoPool = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;

    address constant AerodromeRouter = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;

    address constant HyperlaneMailbox = 0xeA87ae93Fa0019a82A727bfd3eBd1cFCa8f64f1D;

    function setUp() public {}

    function run() public {
        deployBaseMainnet();
    }

    function deployBaseMainnet() public {
        uint256 base_mainnet = vm.createFork(vm.rpcUrl("base_mainnet"));

        vm.selectFork(base_mainnet);

        vm.startBroadcast();

        // Deploy the Handler contract
        Handler base_handler = new Handler(AerodromeRouter);

        console.log("Base Handler Deployed at:", address(base_handler));

        VaultFactory base_factory = new VaultFactory(address(base_handler), 0);

        console.log("Factory Deployed at:", address(base_factory));

        base_handler.updateFactory(address(base_factory));

        VaultDeployer base_deployer = new VaultDeployer(address(base_factory), HyperlaneMailbox);

        console.log("Base Vault Deployer Deployed at:", address(base_deployer));

        base_factory.updateVaultDeployer(address(base_deployer));

        address payable base_vault = payable(base_deployer.deployVault());

        console.log("Base Vault deployed at:", base_vault);

        // Deploying Action Handlers 

        AaveHandler aave_handler = new AaveHandler(AavePool, AavePriceGetter); 

        console.log("Aave Handler Deployed at: ", address(aave_handler));

        MorphoHandler morpho_handler = new MorphoHandler(MorphoPool); 

        console.log("Morpho Handler Deployed at: ", address(morpho_handler));

        // Integrating Condition Handlers with the Handler Contract 
        base_handler.addConditionPlatform(1, address(aave_handler));

        base_handler.addConditionPlatform(2, address(morpho_handler));

        // Integrating Action Handlers with the Handler contract 
        base_handler.addActionPlatform(1, address(aave_handler));

        base_handler.addActionPlatform(2, address(morpho_handler));

        vm.stopBroadcast();
    }
}
