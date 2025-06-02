// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {Script, console} from "forge-std/Script.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";
import {IRouter} from "../../src/interfaces/aerodrome/IRouter.sol";

contract AeroRouterScript is Script {
    address constant AerodromeRouter = 0xcF77a3Ba9A5CA399B7c97c74d54e5b1Beb874E43;

    function run() public {
        simulateSwap();
    }

    function simulateSwap() public {
        uint256 base_mainnet = vm.createFork(vm.rpcUrl("base_mainnet"));

        vm.selectFork(base_mainnet);

        vm.startBroadcast();

        address USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
        address AERO = 0x940181a94A35A4569E4529A3CDfB74e38FD98631;
        uint256 decimal = 10 ** 6;

        IRouter aerodromeRouter = IRouter(AerodromeRouter);

        IERC20 usdc = IERC20(USDC);

        uint256 initial_balance = usdc.balanceOf(address(msg.sender));

        console.log("Initial USDC Balance: ", initial_balance);

        IRouter.Route[] memory route = new IRouter.Route[](1);

        route[0] =
            IRouter.Route({from: USDC, to: AERO, stable: false, factory: 0x420DD381b31aEf6683db6B902084cB0FFECe40Da});

        address pool = aerodromeRouter.poolFor(route[0].from, route[0].to, route[0].stable, route[0].factory);

        console.log("Pool Address: ", pool);

        IERC20(USDC).approve(AerodromeRouter, 2 * decimal);
        console.log("USDC Approved for Aerodrome Router");

        uint256[] memory amounts = aerodromeRouter.getAmountsOut(1 * decimal, route);
        console.log("Expected Amounts: ", amounts[amounts.length - 1]);
        aerodromeRouter.swapExactTokensForTokens(
            1 * decimal, amounts[amounts.length - 1], route, address(msg.sender), block.timestamp + 1000
        );

        vm.stopBroadcast();
    }
}
