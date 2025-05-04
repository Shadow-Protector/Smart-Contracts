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

struct OrderExecutionDetails {
    address token;
    uint256 amount;
    uint8 assetType;
    bool repay;
}

// User Vault
contract Vault {
    // State variables
    address private immutable owner;
    address private immutable factoryContract;
    // Mappings
    mapping(uint32 => address) private chainIdToAddress;
    mapping(bytes32 => OrderDetails) private orders;
    mapping(bytes32 => OrderExecutionDetails) private orderExecutionDetails;
    // Errors

    // Owner Check
    error NotOwner(address sender, address owner);

    error TipAmountIsZero();
    error ConditionValueIsZero();
    error InvalidOrderId(bytes32 orderId);

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
            revert InvalidOrderId(orderId);
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

    function cancelOrder(bytes32 _orderId) public OnlyOwner {
        // Ensure the order ID is valid
        
        OrderDetails memory order = orders[_orderId];

        if (order.tipAmount == 0) {
            revert InvalidOrderId(_orderId);
        }

        
        // Transfer the tip amount back to the sender
        IERC20(order.tipToken).transfer(msg.sender, order.tipAmount);

        // Emit Event order cancellation
        IFactory(factoryContract).emitCancelOrder(owner, _orderId);

        // Broadcast the order cancellation to send funds back to the user
        broadcastOrderCancellation(_orderId, order.destinationChainId);
        
        // Delete the order from the mapping
        delete orders[_orderId];
    }

    function broadcastOrderCancellation(bytes32 orderId, uint32 chainId) internal {

        if(chainId == block.chainid){
            _cancelAssetDeposit(orderId);
        }else{
            // TODO: Broadcast Canceel Asset Deposit to External Chain
        }

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
            revert InvalidOrderId(orderId);
        }

        OrderDetails memory order = orders[orderId];

        if (
            !IFactory(factoryContract).checkCondition(
                _platform, _platformAddress, owner, _parameter, order.conditionValue
            )
        ) {
            revert ConditionEvaluationFailed();
        }

        // TODO:Execute the order

        IERC20(order.tipToken).transfer(_solver, order.tipAmount);

        // Emit Event order execution
        IFactory(factoryContract).emitExecuteOrder(owner, orderId);
    }

    function depositAsset(bytes32 _orderId, address _token, uint256 _tokenAmount, uint8 _assetType, bool _repay)
        external
        OnlyOwner
    {
        // Ensure the order ID is valid
        if (orders[_orderId].tipAmount == 0) {
            revert InvalidOrderId(_orderId);
        }

        if (orderExecutionDetails[_orderId].amount != 0) {
            IERC20(orderExecutionDetails[_orderId].token).transfer(owner, orderExecutionDetails[_orderId].amount);
        }

        orderExecutionDetails[_orderId] =
            OrderExecutionDetails({token: _token, amount: _tokenAmount, assetType: _assetType, repay: _repay});

        // Transfer the token amount
        IERC20(_token).transferFrom(owner, address(this), _tokenAmount);

        // Emit Event of asset Deposit to Factory Contract
        IFactory(factoryContract).emitDepositEvent(owner, _orderId);
    }

    function cancelAssetDeposit(bytes32 _orderId) external OnlyOwner {
        _cancelAssetDeposit(_orderId);
    }

    function _cancelAssetDeposit(bytes32 _orderId) internal {
        // Ensure the order ID is valid
        if (orderExecutionDetails[_orderId].amount == 0) {
            revert InvalidOrderId(_orderId);
        }

        OrderExecutionDetails memory order = orderExecutionDetails[_orderId];
        // Transfer the asset amount back to the sender
        IERC20(order.token).transfer(msg.sender, order.amount);

        // Delete the order execution details from the mapping
        delete orderExecutionDetails[_orderId];

        // Emit Event of asset Deposit cancellation to Factory Contract
        IFactory(factoryContract).emitCancelDeposit(owner, _orderId);
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
