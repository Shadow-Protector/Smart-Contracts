// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

interface IConditionEvaultor {
    function evaluateCondition(
        uint16 _platform,
        address _platformAddress,
        address _borrower,
        uint16 _parameter,
        uint256 _conditionValue
    ) external view returns (bool);
}
