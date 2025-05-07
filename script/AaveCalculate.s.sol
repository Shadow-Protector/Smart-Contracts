// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {AggregatorV3Interface} from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

import {IAavePool} from "../src/interfaces/aave/IAavePool.sol";
import {IPriceOracleGetter} from "../src/interfaces/aave/IAavePriceGetter.sol";

contract CalculateValues is Script {
    function setUp() public {}

    function run() public {
        checkCalculation();
    }

    function checkCalculation() public {
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

        uint256 btc_decimals = 10 ** btc_priceFeed.decimals();

        console.log("btc Price Value: ", btcpriceValue / btc_decimals);

        vm.stopBroadcast();

        vm.selectFork(polygonFork);
        vm.startBroadcast();

        (uint256 totalCollateralBase, uint256 totalDebtBase,,, uint256 ltv, uint256 healthFactor) = IAavePool(
            0x794a61358D6845594F94dc1DB02A252b5b4814aD
        ).getUserAccountData(0xE451141fCE63EB38e85F08a991fC5878Ee6335b2);

        console.log("Total Collateral Base: ", totalCollateralBase);
        console.log("Total Debt Base: ", totalDebtBase);
        console.log("LTV: ", ltv);
        console.log("Health Factor: ", healthFactor);

        console.log("Calling Collateral Parameters");

        uint256 usdc_decimals = 10 ** IERC20(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359).decimals();

        uint256 usdc_price = IPriceOracleGetter(0xb023e699F5a33916Ea823A16485e259257cA8Bd1).getAssetPrice(
            0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
        );

        address aToken = IAavePool(0x794a61358D6845594F94dc1DB02A252b5b4814aD).getReserveAToken(
            0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359
        );

        uint256 collateralBalance = IERC20(aToken).balanceOf(0xE451141fCE63EB38e85F08a991fC5878Ee6335b2);

        console.log("USDC Decimals: ", usdc_decimals);

        console.log("USDC Price: ", usdc_price);

        console.log("Variable Debt Token: ", aToken);

        console.log("Collateral Balance: ", collateralBalance);

        // 4 AM Code Check
        // USDC Decimals:  1000000
        // USDC Price:  99995000
        // Variable Debt Token:  0xA4D94019934D8333Ef880ABFFbF2FDd611C762BD
        // Collateral Balance:  15042176

        console.log("=============================");

        uint256 polygon_decimals = 10 ** IERC20(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270).decimals();

        uint256 polygon_price = IPriceOracleGetter(0xb023e699F5a33916Ea823A16485e259257cA8Bd1).getAssetPrice(
            0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
        );

        address variableDebtToken = IAavePool(0x794a61358D6845594F94dc1DB02A252b5b4814aD).getReserveVariableDebtToken(
            0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270
        );

        uint256 debtBalance = IERC20(variableDebtToken).balanceOf(0xE451141fCE63EB38e85F08a991fC5878Ee6335b2);

        uint256 debtBalanceInBaseCurrency = (debtBalance * polygon_price) / polygon_decimals;

        console.log("Polygon Decimals: ", polygon_decimals);

        console.log("Polygon Price: ", polygon_price);

        console.log("Variable Debt Token: ", variableDebtToken);
        console.log("Debt Balance: ", debtBalance);
        console.log("Debt Balance in Base Currency: ", debtBalanceInBaseCurrency);

        //   Euro Decimals:  100
        //   Euro Price:  112988000
        //   Variable Debt Token:  0x5D557B07776D12967914379C71a1310e917C7555
        //   Debt Balance:  101
        //   Debt Balance in Base Currency:  114117880

        //   Polygon Decimals:  1000000000000000000
        //   Polygon Price:  24136711
        //   Variable Debt Token:  0x4a1c3aD6Ed28a636ee1751C69071f6be75DEb8B8
        //   Debt Balance:  1000000710057617018
        //   Debt Balance in Base Currency:  24136728

        //  Polygon Decimals:  1000000000000000000
        //  Polygon Price:  24240000
        //  Variable Debt Token:  0x4a1c3aD6Ed28a636ee1751C69071f6be75DEb8B8
        //  Debt Balance:  1000028741743584140
        //  Debt Balance in Base Currency:  24240696

        vm.stopBroadcast();
    }
}
