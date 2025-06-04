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

    function setUp() public {}

    function run() public {
        simulationScript();
    }

    function simulationScript() public {
        uint256 arbitrum = vm.createFork(vm.rpcUrl("arbitrum"));

        vm.selectFork(arbitrum);

        vm.startBroadcast();

        VaultFactory arb_factory = new VaultFactory(address(0), 0);

        console.log("Factory Deployed at:", address(arb_factory));

        VaultDeployer arb_deployer = new VaultDeployer(address(arb_factory), 0x979Ca5202784112f4738403dBec5D0F3B9daabB9);

        console.log("Base Vault Deployer Deployed at:", address(arb_deployer));

        arb_factory.updateVaultDeployer(address(arb_deployer));

        address payable arb_vault = payable(arb_deployer.deployVault());

        console.log("arb Vault deployed at:", arb_vault);

        vm.stopBroadcast();
    }
}
