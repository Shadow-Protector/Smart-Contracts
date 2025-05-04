// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IConditionEvaultor} from "./interfaces/IConditionEvaultor.sol";

contract VaultFactory {
    // State Storage Variables
    address private immutable owner;
    address public conditionEvaluator;
    uint256 public platformFee;

    // Mappings
    mapping(address => address) private vaults;

    // Events
    event VaultCreated(address indexed vaultAddress, address indexed owner);

    event OrderCreated(
        uint8 _platform,
        address _platformAddress,
        uint8 _parameter,
        uint32 destinationChainId,
        uint32 _salt,
        uint256 conditionValue,
        address vault
    );

    event OrderCancelled(address indexed vaultAddress, bytes32 indexed orderId);

    event OrderExecuted(address indexed vaultAddress, bytes32 indexed orderId);

    event AssetDeposited(address vaultAddress, bytes32 orderId);

    event UpdatedConditionEvaluator(address indexed newConditionEvaluator, address oldConditionEvaluator);
    // Errors

    error NotOwner(address sender, address owner);

    constructor(address _conditionEvaluator) {
        // Initialize state variables if needed
        owner = msg.sender;
        conditionEvaluator = _conditionEvaluator;
    }

    modifier OnlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender, owner);
        }
        _;
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
        uint8 _platform,
        address _platformAddress,
        uint8 _parameter,
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

    function checkCondition(
        uint8 _platform,
        address _platformAddress,
        address _borrower,
        uint8 _parameter,
        uint256 _conditionValue
    ) external view returns (bool) {
        return IConditionEvaultor(conditionEvaluator).evaluateCondition(
            _platform, _platformAddress, _borrower, _parameter, _conditionValue
        );
    }

    function updateConditionEvaluator(address _newConditionEvaluator) external OnlyOwner {
        emit UpdatedConditionEvaluator(_newConditionEvaluator, conditionEvaluator);
        conditionEvaluator = _newConditionEvaluator;
    }

    function updatePlatformFee(uint256 _newPlatformFee) external OnlyOwner {
        platformFee = _newPlatformFee;
    }

    function addVault(address _vault) external {
        vaults[msg.sender] = _vault;
        emit VaultCreated(_vault, msg.sender);
    }
}
