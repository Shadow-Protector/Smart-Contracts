// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

interface IFactory {
    function emitOrderCreation() external;

    function checkCondition(
        uint8 _platform,
        address _platformAddress,
        address _borrower,
        uint8 _parameter,
        uint256 _conditionValue
    ) external view returns (bool);
}
