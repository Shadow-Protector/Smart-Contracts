// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {AggregatorV3Interface} from "foundry-chainlink-toolkit/src/interfaces/feeds/AggregatorV3Interface.sol";

// /Users/anmolgoyal/dev/base-batch/smart-contracts/lib/foundry-chainlink-toolkit/lib/chainlink-brownie-contracts/contracts/src/interfaces/feeds/AggregatorV3Interface.sol

// Condition parameters (32 bytes)
// -> (platform type) (type = number)
//   -> Chainlink for prices
//   -> Aave Vault Parameters
//   -> Morpho Vault Parameters
//   -> Euler labs Parameters
// -> (Vault or Token Addres) (type = address) (20 bytes )
//   -> Chainlink (Token address for price feed) (Generic)
//   -> Aave Pool Parameters (Pool Address or Vault (!TODO))
//   -> Morpho Vault (address) (Single Contract each chain)
//   -> Euler Vault For Evaulation
// -> (Parameter Categorization) (type = number )
//   -> Chainlink (Lower or Greater )
//   -> Aave (Collateral Value, other params )
//   -> Morpho Params
//   -> Euler Valut parameters
// -> Condition Value (type number) (uint256) (Stored inside the struct)
//   -> Asset Price Value in 18 decimals
//   -> Aave Values
//   -> Morpho Values
//   -> Euler Values

contract ConditionEvaulator {
    address public immutable aavePool;
    address public immutable morphoPool;
    address public immutable eulerPool;

    constructor(address _aavePool, address _morphoPool) {
        aavePool = _aavePool;
        morphoPool = _morphoPool;
    }

    function evaluateCondition(
        uint8 _platform,
        address _borrower,
        address _platformAddress,
        uint8 _parameter,
        uint256 _conditionValue
    ) public view returns (bool) {
        if (_platform == 0) {
            return checkChainlinkCondition(_platformAddress, _parameter, _conditionValue);
        } else if (_platform == 1) {
            return checkAaveCondition();
        } else if (_platform == 2) {
            return checkMorphoCondition();
        } else if (_platform == 3) {
            return checkEulerCondition();
        } else {
            return false;
        }
    }

    function checkChainlinkCondition(address _V3InterfaceAddress, uint8 parameter, uint256 conditionValue)
        public
        view
        returns (bool)
    {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(_V3InterfaceAddress);
        (, int256 price,,,) = priceFeed.latestRoundData();
        uint256 priceValue = uint256(price);

        // Greater than Value
        if (parameter == 0) {
            return conditionValue > priceValue;
        }
        // Less than Value or equal to
        else if (parameter == 1) {
            return conditionValue <= priceValue;
        }

        return false;
    }

    function checkAaveCondition() internal view returns (bool) {}

    function checkMorphoCondition() internal view returns (bool) {}

    function checkEulerCondition() internal view returns (bool) {}
}
