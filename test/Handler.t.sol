// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Handler} from "../src/Handler.sol";

contract ConditionEvaluatorTest is Test {
    Handler public handler;

    function setUp() public {
        // Deploy the ConditionEvaulator contract
        handler = new Handler(address(0), address(0), address(0), address(0));
    }

    // function testEvaluateCondition() public {
    //     // Test the evaluateCondition function with different parameters
    //     uint8 platform = 0; // Chainlink
    //     address platformAddress = address(0);
    //     address borrower = address(0);
    //     uint8 parameter = 1;
    //     uint256 conditionValue = 100;

    //     bool result =
    //         conditionEvaluator.evaluateCondition(platform, platformAddress, borrower, parameter, conditionValue);
    //     assertTrue(result, "Condition evaluation failed");
    // }
}
