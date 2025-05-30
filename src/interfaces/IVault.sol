// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

struct OrderExecutionDetails {
    address token;
    address convert;
    uint256 amount;
    uint16 assetType;
    uint16 platform;
    bool repay;
}

struct OrderDetails {
    uint256 conditionValue;
    // Order Tip Details
    address tipToken;
    uint256 tipAmount;
}

interface IVault {
    function decodeKey(bytes calldata orderId)
        external
        pure
        returns (uint16 platform, address conditionAddress, uint16 parameter, uint32 destinationChainId, uint32 salt);

    function getOrderExecutionDetails(bytes32 orderId)
        external
        view
        returns (address _owner, OrderExecutionDetails memory order);

    function executeOrder(bytes32 _orderId, address _solver) external payable;
}
