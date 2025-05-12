// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Script, console} from "forge-std/Script.sol";

abstract contract ChainIdConfiguration {
    uint256 public constant BASE_SEPOLIA = 84532;

    // uint256 public constant BASE_MAINNET = 84531;
    uint256 public constant ETH_SEPOLIA = 11155111;
    uint256 public constant ARBITRUM_SEPOLIA = 421614;
    uint256 public constant FUJI = 43113;
}

contract HelperConfig is Script, ChainIdConfiguration {
    struct NetworkConfig {
        address hyperlaneMailboxAddress;
        address usdcAddress;
        address tokenMessenger;
        address messageTrasmitter;
        uint32 cctpChainId;
        uint32 cctpValue;
    }

    NetworkConfig public localNetworkConfig;
    mapping(uint256 => NetworkConfig) public networkConfigs;

    constructor() {
        networkConfigs[BASE_SEPOLIA] = getBaseSepoliaConfig();
        networkConfigs[FUJI] = getFujiConfig();
        networkConfigs[ARBITRUM_SEPOLIA] = getArbitrumSepoliaConfig();
        networkConfigs[ETH_SEPOLIA] = getEthSepoliaConfig();
    }

    function getNetworkConfig() public view returns (NetworkConfig memory) {
        if (block.chainid == BASE_SEPOLIA) {
            return networkConfigs[BASE_SEPOLIA];
        } else if (block.chainid == FUJI) {
            return networkConfigs[FUJI];
        } else if (block.chainid == ARBITRUM_SEPOLIA) {
            return networkConfigs[ARBITRUM_SEPOLIA];
        } else if (block.chainid == ETH_SEPOLIA) {
            return networkConfigs[ETH_SEPOLIA];
        } else {
            revert("Unsupported chain");
        }
    }

    function getConfig() public view returns (NetworkConfig memory) {
        return networkConfigs[block.chainid];
    }

    function getEthSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            hyperlaneMailboxAddress: 0xfFAEF09B3cd11D9b20d1a19bECca54EEC2884766,
            usdcAddress: 0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238,
            tokenMessenger: 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA,
            messageTrasmitter: 0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275,
            cctpChainId: 84532,
            cctpValue: 6
        });
    }

    function getBaseSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            hyperlaneMailboxAddress: 0x6966b0E55883d49BFB24539356a2f8A673E02039,
            usdcAddress: 0x036CbD53842c5426634e7929541eC2318f3dCF7e,
            tokenMessenger: 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA,
            messageTrasmitter: 0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275,
            cctpChainId: 43113,
            cctpValue: 1
        });
    }

    function getArbitrumSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            hyperlaneMailboxAddress: 0x598facE78a4302f11E3de0bee1894Da0b2Cb71F8,
            usdcAddress: 0x5425890298aed601595a70AB815c96711a31Bc65,
            tokenMessenger: 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA,
            messageTrasmitter: 0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275,
            cctpChainId: 84532,
            cctpValue: 6
        });
    }

    function getFujiConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            hyperlaneMailboxAddress: 0x5b6CFf85442B851A8e6eaBd2A4E4507B5135B3B0,
            usdcAddress: 0x5425890298aed601595a70AB815c96711a31Bc65,
            tokenMessenger: 0x8FE6B999Dc680CcFDD5Bf7EB0974218be2542DAA,
            messageTrasmitter: 0xE737e5cEBEEBa77EFE34D4aa090756590b1CE275,
            cctpChainId: 84532,
            cctpValue: 6
        });
    }
}
