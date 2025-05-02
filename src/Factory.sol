// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IConditionEvaultor} from "./interfaces/IConditionEvaultor.sol";

contract VaultFactory {
    // State Storage Variables
    address private immutable owner;
    address public conditionEvaluator;

    // Mappings
    mapping(address => address) private vaults;

    // Events
    event VaultCreated(address indexed vaultAddress, address indexed owner);

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

    function emitOrderCreation(
        uint8 _platform,
        address _platformAddress,
        uint8 _parameter,
        uint32 destinationChainId,
        uint32 _salt,
        address _owner
    ) external {}

    function createOrder() external {}

    function executeOrder() external {}

    function cancelOrder() external {}

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
        conditionEvaluator = _newConditionEvaluator;
    }



    function addVault(address _vault) external {
        vaults[msg.sender] = _vault;
        emit VaultCreated(_vault, msg.sender);
    }
}
