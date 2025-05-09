// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.5.0;

import {IERC4626} from "forge-std/interfaces/IERC4626.sol";

interface IMetaMorpho is IERC4626 {
    function deposit(uint256 assets, address receiver) external override returns (uint256 shares);

    function mint(uint256 shares, address receiver) external override returns (uint256 assets);

    function withdraw(uint256 assets, address receiver, address owner) external override returns (uint256 shares);

    function redeem(uint256 shares, address receiver, address owner) external override returns (uint256 assets);
}
