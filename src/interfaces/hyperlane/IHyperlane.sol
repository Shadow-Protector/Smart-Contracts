// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

interface IHyperlaneMailbox {
    function dispatch(uint32 destinationDomain, bytes32 recipientAddress, bytes calldata messageBody)
        external
        payable
        returns (bytes32 messageId);

    function quoteDispatch(uint32 destinationDomain, bytes32 recipientAddress, bytes calldata messageBody)
        external
        view
        returns (uint256 fee);

    function quoteDispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes calldata defaultHookMetadata
    ) external view returns (uint256 fee);

    function dispatch(
        uint32 destinationDomain,
        bytes32 recipientAddress,
        bytes calldata messageBody,
        bytes calldata hookMetadata
    ) external payable returns (bytes32);
}
