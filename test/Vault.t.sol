// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";

import {Handler} from "../src/Handler.sol";
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
    Handler public handler;
    VaultFactory public vaultFactory;
    Vault public vault;
    TokenContract public token;

    function setUp() public {
        // Deploy the ConditionEvaulator contract
        handler = new Handler(address(0), address(0), address(0));

        // Deploy the VaultFactory contract
        vaultFactory = new VaultFactory(address(handler), 0);

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

    function test_bytesSize() public pure {
        uint16 platform = 1;
        address conditionAddress = address(123312); // 20 bytes
        uint16 parameter = 2; // 2 bytes
        uint32 destinationChainId = 8411; // 4 bytes
        uint32 salt = 101;

        bytes memory data = abi.encodePacked(platform, conditionAddress, parameter, destinationChainId, salt);
        assert(data.length == 32);
    }

    function test_decoding() public view {
        uint16 platform = 65500;
        address conditionAddress = address(0xA01f6403d49857b58D3794C12E028c3681b24F98); // 20 bytes
        uint16 parameter = 45500; // 2 bytes
        uint32 destinationChainId = 84111; // 4 bytes
        uint32 salt = 10100;

        bytes32 orderId = vault.generateKey(platform, conditionAddress, parameter, destinationChainId, salt);

        console.logBytes32(orderId);

        (
            uint16 check_platform,
            address check_conditionAddress,
            uint16 check_parameter,
            uint32 check_destinationChainId,
            uint32 check_salt
        ) = vault.decodeKey(abi.encodePacked(orderId));

        console.log("Plaform", platform, check_platform);
        assert(platform == check_platform);

        console.log("Condition Address", conditionAddress, check_conditionAddress);
        assert(conditionAddress == check_conditionAddress);

        console.log("Parameter", parameter, check_parameter);
        assert(parameter == check_parameter);

        console.log("ChainId", destinationChainId, check_destinationChainId);
        assert(destinationChainId == check_destinationChainId);

        console.log("Salt", salt, check_salt);
        assert(salt == check_salt);
    }
}
