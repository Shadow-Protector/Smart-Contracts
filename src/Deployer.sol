// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Vault} from "./Vault.sol";
import {IFactory} from "./interfaces/IFactory.sol";

/// @title Vault Deployer
/// @author Shadow Protector, @parizval
/// @notice Vault Deployer allows deploying of new User Vaults.
contract VaultDeployer {
    address private owner;
    address public factory;
    address public hyperlaneMailbox;

    error NotOwner(address sender, address owner);

    constructor(address _factory, address _hyperlaneMailbox) {
        owner = msg.sender;
        factory = _factory;
        hyperlaneMailbox = _hyperlaneMailbox;
    }

    modifier OnlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender, owner);
        }
        _;
    }

    function updateOwner(address _newOwner) external OnlyOwner {
        owner = _newOwner;
    }

    function updateFactory(address _newFactory) external OnlyOwner {
        factory = _newFactory;
    }

    function updateHyperlaneMailbox(address _newHyperlaneMailbox) external OnlyOwner {
        hyperlaneMailbox = _newHyperlaneMailbox;
    }

    function deployVault() external returns (address) {
        Vault vault = new Vault(msg.sender, factory, hyperlaneMailbox);

        IFactory(factory).addVault(address(vault), msg.sender);

        return address(vault);
    }
}
