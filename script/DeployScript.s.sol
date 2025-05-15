// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {Handler} from "../src/Handler.sol";
import {VaultFactory} from "../src/Factory.sol";
import {VaultDeployer} from "../src/Deployer.sol";

contract DeployScript is Script {
    function setUp() public {}

    function run() public {
        deployScript();
    }

    function deployScript() public {
        uint256 baseSepoliaFork = vm.createFork(vm.rpcUrl("base_sepolia"));

        vm.selectFork(baseSepoliaFork);

        vm.startBroadcast();

        // Deploy the Handler contract
        Handler handler = new Handler(address(0), address(0), address(0), address(0));

        console.log("Handler Deployed at:", address(handler));

        VaultFactory factory = new VaultFactory(address(handler), 0);

        console.log("Factory Deployed at:", address(factory));

        VaultDeployer deployer = new VaultDeployer(address(factory), address(0));

        console.log("Vault deployer at:", address(deployer));

        // Configuration of contracts

        handler.updateFactory(address(factory));
        factory.updateVaultDeployer(address(deployer));

        deployer.deployVault();

        vm.stopBroadcast();
    }
}
