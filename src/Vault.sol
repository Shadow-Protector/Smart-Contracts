// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHyperlaneMailbox} from "./interfaces/IHyperlane.sol";
import {StandardHookMetadata} from "./interfaces/HyperlaneHook.sol";

import {IFactory} from "./interfaces/IFactory.sol";

// Operation Codes
// 0: Cancel Order
// 1: Execute Order with Supply
// 2: Execute Order with Repay

struct OrderDetails {
    uint256 conditionValue;
    // Order Tip Details
    address tipToken;
    uint256 tipAmount;
}

struct OrderExecutionDetails {
    address token;
    address convert;
    uint256 amount;
    uint8 assetType;
    uint8 platform;
    bool repay;
}

// User Vault
contract Vault {
    // State variables
    address private immutable owner;
    address private immutable factoryContract;
    address private immutable hyperlaneMailbox;
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

    error SenderNotMailbox(address caller);

    error InvalidSender(bytes32 sender);
    error NotHandler(address handler, address sender);

    constructor(address _owner, address _factoryContract, address _hyperlaneMailbox) {
        owner = _owner;
        factoryContract = _factoryContract;
        hyperlaneMailbox = _hyperlaneMailbox;
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

        if (orders[orderId].tipAmount != 0) {
            revert InvalidOrderId(orderId);
        }

        // Create the order details
        OrderDetails memory newOrder =
            OrderDetails({conditionValue: conditionValue, tipToken: tipToken, tipAmount: tipAmount});

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

        (,,, uint32 destinationChainId,) = this.decodeKey(abi.encodePacked(_orderId));

        // Transfer the tip amount back to the sender
        IERC20(order.tipToken).transfer(msg.sender, order.tipAmount);

        // Emit Event order cancellation
        IFactory(factoryContract).emitCancelOrder(owner, _orderId);

        // Broadcast the order cancellation to send funds back to the user
        broadcastOrderCancellation(_orderId, destinationChainId);

        // Delete the order from the mapping
        delete orders[_orderId];
    }

    function broadcastOrderCancellation(bytes32 orderId, uint32 chainId) internal {
        if (chainId == block.chainid) {
            _cancelAssetDeposit(orderId);
        } else {
            // Broadcast Canceel Asset Deposit to External Chain
            sendMessageToDestinationChain(chainId, orderId, 0);
        }
    }

    function executeOrder(bytes32 _orderId, address _solver) public payable {
        (uint16 platform, address platformAddress, uint16 parameter, uint32 destinationChainId,) =
            this.decodeKey(abi.encodePacked(_orderId));

        // Ensure the order ID is valid
        if (orders[_orderId].tipAmount == 0) {
            revert InvalidOrderId(_orderId);
        }

        OrderDetails memory order = orders[_orderId];

        if (
            !IFactory(factoryContract).checkCondition(platform, platformAddress, owner, parameter, order.conditionValue)
        ) {
            revert ConditionEvaluationFailed();
        }

        // TODO:Execute the order
        _executeOrder(_orderId, destinationChainId);

        IERC20(order.tipToken).transfer(_solver, order.tipAmount);

        // Emit Event order execution
        IFactory(factoryContract).emitExecuteOrder(owner, _orderId);
    }

    function _executeOrder(bytes32 orderId, uint32 chainId) internal {
        if (chainId == block.chainid) {
            // TODO: Order Execution
            address handler = IFactory(factoryContract).getHandler();
            if (msg.sender != handler) {
                revert NotHandler(handler, msg.sender);
            }
        } else {
            // Broadcast Execute Oder to External Chain
            sendMessageToDestinationChain(chainId, orderId, 1);
        }
    }

    function depositAsset(
        bytes32 _orderId,
        address _token,
        address _convert,
        uint256 _tokenAmount,
        uint8 _platform,
        uint8 _assetType,
        bool _repay
    ) external payable OnlyOwner {
        if (orderExecutionDetails[_orderId].amount != 0) {
            IERC20(orderExecutionDetails[_orderId].token).transfer(owner, orderExecutionDetails[_orderId].amount);
        }

        orderExecutionDetails[_orderId] = OrderExecutionDetails({
            token: _token,
            convert: _convert,
            amount: _tokenAmount,
            platform: _platform,
            assetType: _assetType,
            repay: _repay
        });

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

    function sendMessageToDestinationChain(uint32 destinationChainId, bytes32 orderId, uint8 Operation) internal {
        // Call Hyperlane to send the message to the destination chain
        IHyperlaneMailbox mailBox = IHyperlaneMailbox(hyperlaneMailbox);
        bytes32 recipientAddress = addressToBytes32(chainIdToAddress[destinationChainId]);

        bytes memory HookMetadata = StandardHookMetadata.overrideGasLimit(500000);

        bytes memory messageBody = abi.encode(orderId, Operation);

        uint256 fee = mailBox.quoteDispatch(destinationChainId, recipientAddress, messageBody, HookMetadata);

        mailBox.dispatch{value: fee}(destinationChainId, recipientAddress, messageBody, HookMetadata);
    }

    function handle(uint32 _origin, bytes32 _sender, bytes calldata _message) external payable {
        // Ensure the function is called by Hyperlane
        if (msg.sender != hyperlaneMailbox) {
            revert SenderNotMailbox(msg.sender);
        }

        address originAddress = chainIdToAddress[_origin];

        // Check if the message is from valid sender
        if (_sender != addressToBytes32(originAddress)) {
            revert InvalidSender(_sender);
        }
        // Decode the message to get the order ID
        (bytes32 orderId, uint8 operation) = abi.decode(_message, (bytes32, uint8));

        OrderExecutionDetails memory orderExecution = orderExecutionDetails[orderId];
        if (orderExecution.amount == 0) {
            revert InvalidOrderId(orderId);
        }

        if (operation == 0) {
            // Cancel Order
            _cancelAssetDeposit(orderId);
        }
        // TODO: Handle supply and repay operations
    }

    function rescueFunds(address _token, uint256 _amount) external OnlyOwner {
        IERC20(_token).transfer(owner, _amount);
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
        uint16 platform, // 2 bytes
        address conditionAddress, // 20 bytes
        uint16 parameter, // 2 bytes
        uint32 destinationChainId, // 4 bytes
        uint32 salt // 4 bytes
    ) public pure returns (bytes32) {
        bytes memory data = abi.encodePacked(platform, conditionAddress, parameter, destinationChainId, salt);
        assert(data.length == 32);
        return bytes32(data);
    }

    function decodeKey(bytes calldata orderId)
        public
        pure
        returns (uint16 platform, address conditionAddress, uint16 parameter, uint32 destinationChainId, uint32 salt)
    {
        require(orderId.length == 32, "Expected exactly 32 bytes");

        assembly {
            // platform: uint16 at offset 0 (2 bytes)
            platform := shr(240, calldataload(orderId.offset)) // shift right by 30 bytes

            // conditionAddress: address at offset 2 (20 bytes)
            conditionAddress := shr(96, calldataload(add(orderId.offset, 2))) // shift right by 12 bytes

            // parameter: uint16 at offset 22
            parameter := shr(240, calldataload(add(orderId.offset, 22)))

            // destinationChainId: uint32 at offset 24
            destinationChainId := shr(224, calldataload(add(orderId.offset, 24))) // shift right by 28 bytes

            // salt: uint32 at offset 28
            salt := shr(224, calldataload(add(orderId.offset, 28)))
        }
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
