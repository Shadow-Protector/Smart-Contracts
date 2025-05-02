// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IFactory} from "./interfaces/IFactory.sol";

struct OrderDetails {
    uint32 destinationChainId;
    uint256 conditionValue;
    // Order Tip Details
    address tipToken;
    uint256 tipAmount;
}

// User Vault
contract Vault {
    // State variables
    address private immutable owner;
    address private immutable factoryContract;
    // Mappings
    mapping(uint32 => address) private chainIdToAddress;
    mapping(bytes32 => OrderDetails) private orders;

    // Errors

    // Owner Check
    error NotOwner(address sender, address owner);

    error TipAmountIsZero();
    error ConditionValueIsZero();
    error InvalidOrderId();

    error ConditionEvaluationFailed();

    constructor(address _owner, address _factoryContract) {
        owner = _owner;
        factoryContract = _factoryContract;
    }

    modifier OnlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender, owner);
        }
        _;
    }

    receive() external payable {
        // Function to receive Ether. msg.data must be empty
    }

    function createOrder(
        uint8 _platform,
        address _platformAddress,
        uint8 _parameter,
        uint32 destinationChainId,
        uint32 _salt,
        uint256 conditionValue,
        address tipToken,
        uint256 tipAmount
    ) public payable OnlyOwner {
        // Ensure the condition amount is greater than zero
        if (conditionValue == 0) {
            revert ConditionValueIsZero();
        }
        // Ensure the tip amount is greater than zero
        if (tipAmount == 0) {
            revert TipAmountIsZero();
        }

        bytes32 orderId = generateKey(_platform, _platformAddress, _parameter, destinationChainId, _salt);

        if (orders[orderId].tipAmount == 0) {
            revert InvalidOrderId();
        }

        // Create the order details
        OrderDetails memory newOrder = OrderDetails({
            destinationChainId: destinationChainId,
            conditionValue: conditionValue,
            tipToken: tipToken,
            tipAmount: tipAmount
        });

        // Store the order in the mapping
        orders[orderId] = newOrder;

        // Transfer the tip amount from the sender to the contract
        IERC20(tipToken).transferFrom(msg.sender, address(this), tipAmount);

        // Emit Event order creation
        IFactory(factoryContract).emitOrderCreation{value: msg.value}(
            _platform, _platformAddress, _parameter, destinationChainId, _salt, conditionValue, owner
        );
    }

    function cancelOrder(bytes32 orderId) public OnlyOwner {
        // Ensure the order ID is valid
        if (orders[orderId].tipAmount == 0) {
            revert InvalidOrderId();
        }
        // Transfer the tip amount back to the sender
        IERC20(orders[orderId].tipToken).transfer(msg.sender, orders[orderId].tipAmount);

        // Delete the order from the mapping
        delete orders[orderId];

        // Emit Event order cancellation
        IFactory(factoryContract).emitCancelOrder(owner, orderId);
    }

    function executeOrder(
        uint8 _platform,
        address _platformAddress,
        uint8 _parameter,
        uint32 destinationChainId,
        uint32 _salt,
        address _solver
    ) public payable {
        bytes32 orderId = generateKey(_platform, _platformAddress, _parameter, destinationChainId, _salt);

        // Ensure the order ID is valid
        if (orders[orderId].tipAmount == 0) {
            revert InvalidOrderId();
        }

        OrderDetails memory order = orders[orderId];

        if (
            !IFactory(factoryContract).checkCondition(
                _platform, _platformAddress, owner, _parameter, order.conditionValue
            )
        ) {
            revert ConditionEvaluationFailed();
        }

        // Execute the order

        IERC20(order.tipToken).transfer(_solver, order.tipAmount);

        // Emit Event order execution
        IFactory(factoryContract).emitExecuteOrder(owner, orderId);
    }

    function withdrawNativeToken(uint256 _amount) external OnlyOwner {
        payable(owner).transfer(_amount);
    }

    function addExternalChainVault(uint32 chainId, address chainAddress) external OnlyOwner {
        chainIdToAddress[chainId] = chainAddress;
    }

    function getExternalChainVault(uint32 chainId) external view returns (address) {
        return chainIdToAddress[chainId];
    }

    function generateKey(
        uint8 platform,
        address conditionAddress,
        uint8 parameter,
        uint32 destinationChainId,
        uint32 salt
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(platform, conditionAddress, parameter, destinationChainId, salt));
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
