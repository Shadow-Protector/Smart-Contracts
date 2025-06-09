// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

interface IActionHandler {
    function evaluateCondition(
        uint16 _platform,
        address _platformAddress,
        address _borrower,
        uint16 _parameter,
        uint256 _conditionValue
    ) external view returns (bool);

    function getDepositToken(address token, uint16 assetType) external view returns (address);

    function unWindPosition(address token, uint16 assetType, uint256 amount, address handler) external returns (uint256);

    function handleDeposit(address token, uint256 amount, address _owner, bool repay) external;
}
