// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

import {IAavePool} from "../src/interfaces/IAavePool.sol";
import {IPriceOracleGetter} from "../src/interfaces/IAavePriceGetter.sol";

contract CalculateValues is Script {

    function setUp() public {}


    function run() public {
        checkCalculation();
    }


    function checkCalculation() public{

        uint256 polygonFork = vm.createFork(vm.rpcUrl("polygon_pos_mainnet"));

        uint256 baseFork = vm.createFork(vm.rpcUrl("base_mainnet"));

        vm.selectFork(baseFork);

        vm.startBroadcast();

        AggregatorV3Interface Eth_priceFeed = AggregatorV3Interface(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70);
        (, int256 eth_price,,,) = Eth_priceFeed.latestRoundData();
        uint256 ethpriceValue = uint256(eth_price);

        console.log("Eth Price Value: ", ethpriceValue);


        AggregatorV3Interface btc_priceFeed = AggregatorV3Interface(0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F);
        (, int256 btc_price,,,) = btc_priceFeed.latestRoundData();
        uint256 btcpriceValue = uint256(btc_price);

        uint256 btc_decimals = 10** btc_priceFeed.decimals();

        console.log("btc Price Value: ", btcpriceValue / btc_decimals);

        vm.stopBroadcast();

        vm.selectFork(polygonFork);
        vm.startBroadcast();

        (uint256 totalCollateralBase, uint256 totalDebtBase,,, uint256 ltv, uint256 healthFactor) = IAavePool(0x794a61358D6845594F94dc1DB02A252b5b4814aD).getUserAccountData(0xE451141fCE63EB38e85F08a991fC5878Ee6335b2);

        console.log("Total Collateral Base: ", totalCollateralBase);
        console.log("Total Debt Base: ", totalDebtBase);
        console.log("LTV: ", ltv);
        console.log("Health Factor: ", healthFactor);


        vm.stopBroadcast();

    }

}

