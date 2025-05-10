// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IOracle} from "../src/interfaces/morpho/IMorphoOracle.sol";
import {IMorpho, MarketParams, Id, Position, Market} from "../src/interfaces/morpho/IMorpho.sol";
import {MathLib, WAD} from "../src/lib/MathLib.sol";
import {SharesMathLib} from "../src/lib/SharesMathLib.sol";

contract MorphoCalculation is Script {
    using MathLib for uint256;
    using SharesMathLib for uint256;

    function setUp() public {}

    function run() public {
        checkCalculation();
    }

    function checkCalculation() public {
        uint256 baseFork = vm.createFork(vm.rpcUrl("base_mainnet"));

        bytes32 market = 0x13c42741a359ac4a8aa8287d2be109dcf28344484f91185f9a79bd5a805a55ae;

        vm.selectFork(baseFork);

        vm.startBroadcast();

        IMorpho morpho = IMorpho(0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb);

        MarketParams memory params = morpho.idToMarketParams(Id.wrap(market));

        console.log("Market loanToken", params.loanToken);

        console.log("Market collateralToken", params.collateralToken);

        console.log("Oracle", params.oracle);

        console.log("LLTV", params.lltv / 1e16);
        //  860_000_000_000_000_000

        IOracle oracle = IOracle(params.oracle);

        uint256 price = oracle.price();

        console.log("Price", price);

        Position memory position = morpho.position(Id.wrap(market), 0xE451141fCE63EB38e85F08a991fC5878Ee6335b2);

        console.log("Position Collateral", position.collateral);

        Market memory marketData = morpho.market(Id.wrap(market));

        uint256 borrowed =
            uint256(position.borrowShares).toAssetsUp(marketData.totalBorrowAssets, marketData.totalBorrowShares);

        console.log("Borrowed", borrowed);

        uint256 maxBorrow = uint256(position.collateral).mulDivDown(price, 1e36).wMulDown(params.lltv);

        console.log("Max Borrow", maxBorrow);

        uint8 decimals = 34 + IERC20(params.loanToken).decimals() - IERC20(params.collateralToken).decimals();

        console.log("Price", price / 10 ** decimals);

        vm.stopBroadcast();
    }
}
