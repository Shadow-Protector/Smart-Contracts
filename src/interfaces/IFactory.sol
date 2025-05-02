// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

interface IFactory {
    function emitOrderCreation(
        uint8 _platform,
        address _platformAddress,
        uint8 _parameter,
        uint32 destinationChainId,
        uint32 _salt,
        uint256 conditionValue,
        address _vaultOwner
    ) external payable;

    function emitExecuteOrder(address _vaultOwner, bytes32 OrderId) external;

    function emitCancelOrder(address _vaultOwner, bytes32 OrderId) external;

    function checkCondition(
        uint8 _platform,
        address _platformAddress,
        address _borrower,
        uint8 _parameter,
        uint256 _conditionValue
    ) external view returns (bool);
}
