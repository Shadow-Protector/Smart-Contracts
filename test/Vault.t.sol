// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";

import {ConditionEvaulator} from "../src/ConditionEvaulator.sol";
import {VaultFactory} from "../src/Factory.sol";
import {Vault} from "../src/Vault.sol";
import {ERC20} from "openzeppelin-contracts/contracts/token/ERC20/ERC20.sol";

contract TokenContract is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address account, uint256 amount) public {
        _mint(account, amount);
    }
}

contract VaultTest is Test {
    ConditionEvaulator public conditionEvaulator;
    VaultFactory public vaultFactory;
    Vault public vault;
    TokenContract public token;

    function setUp() public {
        // Deploy the ConditionEvaulator contract
        conditionEvaulator = new ConditionEvaulator(address(0), address(0));

        // Deploy the VaultFactory contract
        vaultFactory = new VaultFactory(address(conditionEvaulator), address(0), 0);

        // Deploy the Vault contract
        vault = new Vault(address(123), address(vaultFactory), address(0));

        // Deploy the ERC20 token contract
        token = new TokenContract("TestToken", "TTK");
        token.mint(address(123), 1000 * 10 ** 18); // Mint 1000 tokens to this contract
    }

    function test_flow() public {
        vm.startPrank(address(123));

        assert(token.balanceOf(address(123)) == 1000 * 10 ** 18);

        // Add Vault to the factory registry
        vaultFactory.addVault(address(vault));

        // Approve the vault to spend tokens
        token.approve(address(vault), 100 * 10 ** 18); // Approve 100 tokens

        // Create Limit Order s
        vault.createOrder(0, address(0), 0, uint32(block.chainid), 0, 1, address(token), 10 * 10 ** 18);

        assert(token.balanceOf(address(vault)) == 10 * 10 ** 18);
    }
}
