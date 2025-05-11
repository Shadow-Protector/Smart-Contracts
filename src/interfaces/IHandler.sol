// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

interface IHandler {
    function evaluateCondition(
        uint16 _platform,
        address _platformAddress,
        address _borrower,
        uint16 _parameter,
        uint256 _conditionValue
    ) external view returns (bool);

    function getDepositToken(address token, uint16 assetType) external view returns (address);

    function executeCrossChainOrder(address vault, bytes32 orderId, uint32 destinationChainId) external;
}
