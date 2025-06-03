// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

struct CrossChainData {
    address usdc;
    address tokenMessenger;
    address messageTransmitter;
    address handler;
    uint32 destinationDomain;
}

interface IFactory {
    function emitOrderCreation(
        uint16 _platform,
        address _platformAddress,
        uint16 _parameter,
        uint32 destinationChainId,
        uint32 _salt,
        uint256 conditionValue,
        address _vaultOwner,
        bytes32 orderId
    ) external payable;

    function addVault(address _vault, address _owner) external;

    function executeCrossChainOrder(address vaultOwner, bytes32 orderId, uint32 destinationChainId) external;

    function emitExecuteOrder(address _vaultOwner, bytes32 OrderId) external;

    function emitCancelOrder(address _vaultOwner, bytes32 OrderId) external;

    function emitDepositEvent(address _vaultOwner, bytes32 _orderId, address depositToken, address convertToken)
        external;

    function emitCancelDeposit(address _vaultOwner, bytes32 _orderId) external;

    function emitCrossChainHook(bytes32 orderId) external;

    function checkCondition(
        uint16 _platform,
        address _platformAddress,
        address _borrower,
        uint16 _parameter,
        uint256 _conditionValue
    ) external view returns (bool);

    function getTipForCrossChainOrder(bytes32 _orderId, address _owner, address _solver) external;

    function getHandler() external view returns (address);

    function getDepositToken(address token, uint16 assetType) external view returns (address);

    function platformFee() external view returns (uint256);

    function getCrossChainData(uint32 _chainId)
        external
        view
        returns (address usdc, address tokenMessenger, CrossChainData memory);

    function getMessageTransmitter() external view returns (address messageTransmitter, address usdc);
}
