// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IHandler} from "./interfaces/IHandler.sol";

contract VaultFactory {
    // State Storage Variables
    address private owner;
    address public handler;
    uint256 public platformFee;

    // Mappings
    mapping(address => address) private vaults;

    // Events
    event VaultCreated(address indexed vaultAddress, address indexed owner);

    event UpdatedOwner(address oldOwner, address newOwner);

    event OrderCreated(
        uint16 _platform,
        address _platformAddress,
        uint16 _parameter,
        uint32 destinationChainId,
        uint32 _salt,
        uint256 conditionValue,
        address vault
    );

    event OrderCancelled(address indexed vaultAddress, bytes32 indexed orderId);

    event OrderExecuted(address indexed vaultAddress, bytes32 indexed orderId);

    event AssetDeposited(address vaultAddress, bytes32 orderId);

    event CancelDeposit(address vaultAddress, bytes32 orderId);

    event UpdatedHandler(address indexed newConditionEvaluator, address oldConditionEvaluator);
    // Errors

    error NotOwner(address sender, address owner);

    constructor(address _handler, uint256 _platformFee) {
        // Initialize state variables if needed
        owner = msg.sender;
        handler = _handler;
        platformFee = _platformFee;
    }

    modifier OnlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender, owner);
        }
        _;
    }

    function updateOwner(address _newOwner) external OnlyOwner {
        emit UpdatedOwner(owner, _newOwner);
        owner = _newOwner;
    }

    // Platform Fee in gas token

    function emitOrderCreation(
        uint8 _platform,
        address _platformAddress,
        uint8 _parameter,
        uint32 destinationChainId,
        uint32 _salt,
        address _owner
    ) external {}

    function emitOrderCreation(
        uint16 _platform,
        address _platformAddress,
        uint16 _parameter,
        uint32 destinationChainId,
        uint32 _salt,
        uint256 conditionValue,
        address _vaultOwner
    ) external payable {
        assert(msg.value >= platformFee);

        assert(msg.sender == vaults[_vaultOwner]);

        emit OrderCreated(
            _platform, _platformAddress, _parameter, destinationChainId, _salt, conditionValue, msg.sender
        );
    }

    function emitExecuteOrder(address _vaultOwner, bytes32 OrderId) external {
        assert(msg.sender == vaults[_vaultOwner]);

        emit OrderExecuted(msg.sender, OrderId);
    }

    function emitCancelOrder(address _vaultOwner, bytes32 OrderId) external {
        assert(msg.sender == vaults[_vaultOwner]);

        emit OrderCancelled(msg.sender, OrderId);
    }

    function emitDepositEvent(address _vaultOwner, bytes32 _orderId) external {
        assert(msg.sender == vaults[_vaultOwner]);

        emit AssetDeposited(msg.sender, _orderId);
    }

    function emitCancelDeposit(address _vaultOwner, bytes32 _orderId) external {
        assert(msg.sender == vaults[_vaultOwner]);

        emit CancelDeposit(msg.sender, _orderId);
    }

    function checkCondition(
        uint16 _platform,
        address _platformAddress,
        address _borrower,
        uint16 _parameter,
        uint256 _conditionValue
    ) external view returns (bool) {
        return IHandler(handler).evaluateCondition(_platform, _platformAddress, _borrower, _parameter, _conditionValue);
    }

    function getDepositToken(address token, uint16 assetType) external view returns (address) {
        return IHandler(handler).getDepositToken(token, assetType);
    }

    function updateHandler(address _newHandler) external OnlyOwner {
        emit UpdatedHandler(handler, _newHandler);
        handler = _newHandler;
    }

    function updatePlatformFee(uint256 _newPlatformFee) external OnlyOwner {
        platformFee = _newPlatformFee;
    }

    function addVault(address _vault) external {
        vaults[msg.sender] = _vault;
        emit VaultCreated(_vault, msg.sender);
    }

    function getHandler() external view returns (address) {
        return handler;
    }
}
