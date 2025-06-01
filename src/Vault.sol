// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IHyperlaneMailbox} from "./interfaces/hyperlane/IHyperlane.sol";
import {StandardHookMetadata} from "./interfaces/hyperlane/HyperlaneHook.sol";

import {IFactory} from "./interfaces/IFactory.sol";

import {IVault, OrderDetails, OrderExecutionDetails} from "./interfaces/IVault.sol";

// Operation Codes
// 0: Cancel Order
// 1: Execute Order with Supply
// 2: Execute Order with Repay
// 3: Send Tip to Solver for Cross-Chain Order

/// @title Vault Deployer
/// @author Shadow Protector, @parizval
/// @notice Vault allows users to create, deposit, cancel and handle cross-chain
contract Vault is IVault {
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
    error SenderNotFactory(address caller);

    error InvalidCrossChainSender(bytes32 sender);
    error CrossChainConditionNotMet(bytes32 orderId);
    error NotHandler(address handler, address sender);
    error NotSufficientOrderCreationFee(uint256 currentBalance, uint256 platformFee);

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
        uint16 _platform,
        address _platformAddress,
        uint16 _parameter,
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

        // Store the order in the mapping
        orders[orderId] = OrderDetails({
            conditionValue: conditionValue,
            tipToken: tipToken,
            tipAmount: tipAmount,
            crossChainActive: false
        });

        // Transfer the tip amount from the sender to the contract
        IERC20(tipToken).transferFrom(msg.sender, address(this), tipAmount);

        // Get Platform Fee from Factory Contract
        uint256 platformFee = IFactory(factoryContract).platformFee();

        if (address(this).balance < platformFee) {
            revert NotSufficientOrderCreationFee(address(this).balance, platformFee);
        }

        // Emit Event order creation
        IFactory(factoryContract).emitOrderCreation{value: platformFee}(
            _platform, _platformAddress, _parameter, destinationChainId, _salt, conditionValue, owner, orderId
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
            if (address(this).balance != 0) {
                // Broadcast Canceel Asset Deposit to External Chain
                sendMessageToDestinationChain(chainId, orderId, 0);
            }
        }
    }

    function executeOrder(bytes32 _orderId, address _solver) external payable {
        address handler = IFactory(factoryContract).getHandler();

        if (msg.sender != handler) {
            revert NotHandler(handler, msg.sender);
        }

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

        // TODO:Execute the order for cross-chain order
        _executeOrder(_orderId, destinationChainId, handler);

        IERC20(order.tipToken).transfer(_solver, order.tipAmount);

        // Emit Event order execution
        IFactory(factoryContract).emitExecuteOrder(owner, _orderId);
    }

    function _executeOrder(bytes32 orderId, uint32 chainId, address handler) internal {
        if (chainId == block.chainid) {
            // Order Execution would be handled by handler contract
            OrderExecutionDetails memory order = orderExecutionDetails[orderId];

            // Get the deposit token address
            address depositToken = IFactory(factoryContract).getDepositToken(order.token, order.assetType);

            IERC20(depositToken).approve(handler, order.amount);

            // Deleting the order condition details
            delete orders[orderId];
        } else {
            // Ensure the cross-chain order condition was met
            orders[orderId].crossChainActive = true;
            // Broadcast Execute Oder to External Chain
            sendMessageToDestinationChain(chainId, orderId, 1);
        }

        // Deleting the order execution details
        delete orderExecutionDetails[orderId];
    }

    function depositAsset(
        bytes32 _orderId,
        address _token,
        uint16 _assetType,
        address _convert,
        uint256 _tokenAmount,
        uint16 _platform,
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

        address depositToken = IFactory(factoryContract).getDepositToken(_token, _assetType);

        // Transfer the token amount
        IERC20(depositToken).transferFrom(owner, address(this), _tokenAmount);

        // Emit Event of asset Deposit to Factory Contract
        IFactory(factoryContract).emitDepositEvent(owner, _orderId, _token, _convert);
    }

    function cancelAssetDeposit(bytes32 _orderId) external OnlyOwner {
        _cancelAssetDeposit(_orderId);
    }

    function sendTipForCrossChainOrder(bytes32 _orderId, address _solver) external {
        if (msg.sender != factoryContract) {
            revert SenderNotFactory(msg.sender);
        }

        // Ensure the order ID is valid
        OrderDetails memory order = orders[_orderId];

        if (!order.crossChainActive) {
            revert CrossChainConditionNotMet(_orderId);
        }

        IERC20(order.tipToken).transfer(_solver, order.tipAmount);

        delete orders[_orderId];
    }

    function _cancelAssetDeposit(bytes32 _orderId) internal {
        // Ensure the order ID is valid
        OrderExecutionDetails memory order = orderExecutionDetails[_orderId];

        if (order.amount != 0) {
            // Get the deposit token address
            address depositToken = IFactory(factoryContract).getDepositToken(order.token, order.assetType);
            // Transfer the asset amount back to the sender
            IERC20(depositToken).transfer(owner, order.amount);

            // Delete the order execution details from the mapping
            delete orderExecutionDetails[_orderId];

            // Emit Event of asset Deposit cancellation to Factory Contract
            IFactory(factoryContract).emitCancelDeposit(owner, _orderId);

            // Deleting the order execution details
            delete orderExecutionDetails[_orderId];
        }
    }

    // TODO: Update message parameters to adjust deposit vaults
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
            revert InvalidCrossChainSender(_sender);
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
        // Call Handler to create a cow swap order and bridge the asset
        if (operation == 1 || operation == 2) {
            // Get the handler
            address handler = IFactory(factoryContract).getHandler();
            // Get the deposit token address
            address depositToken =
                IFactory(factoryContract).getDepositToken(orderExecution.token, orderExecution.assetType);
            // approve the handler
            IERC20(depositToken).approve(handler, orderExecution.amount);
            // Call the factory for cross-chain order execution
            IFactory(factoryContract).executeCrossChainOrder(owner, orderId, _origin);
        }
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

    function getOrderExecutionDetails(bytes32 orderId)
        external
        view
        returns (address _owner, OrderExecutionDetails memory order)
    {
        return (owner, orderExecutionDetails[orderId]);
    }

    function addressToBytes32(address _addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(_addr)));
    }
}
