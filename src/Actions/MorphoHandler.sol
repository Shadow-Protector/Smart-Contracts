// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IOracle} from "../interfaces/morpho/IMorphoOracle.sol";
import {IMorpho, MarketParams, Id, Position, Market} from "../../src/interfaces/morpho/IMorpho.sol";
import {IMetaMorpho} from "../interfaces/morpho/IMetaMorpho.sol";
import {IIrm} from "../interfaces/morpho/IIrm.sol";

import {MathLib, WAD} from "../lib/MathLib.sol";
import {SharesMathLib} from "../lib/SharesMathLib.sol";
import {UtilsLib} from "../lib/UtilsLib.sol";
import {IActionHandler} from "../interfaces/IActionHandler.sol";

// TODO: Add Logic to Update Stale MarketData

/// @title MorphoHandler
/// @author Shadow Protector, @parizval
/// @notice Handles all the logic for Morpho Protocol Integration
contract MorphoHandler is IActionHandler {
    using MathLib for uint256;
    using SharesMathLib for uint256;
    using UtilsLib for uint256;

    using MathLib for uint128;

    // Storage
    address public owner;

    IMorpho public immutable morphoPool;
    mapping(address => bytes32) public morphoMarket;
    mapping(address => address) public morphoVaults;

    // Events
    event UpdatedOwner(address oldOwner, address newOwner);
    event MorphoMarketAdded(address market, bytes32 id);
    event MorphoVaultAdded(address vault, address vaultId);

    // Errors
    error NotOwner(address sender, address owner);
    error MorphoMarketNotFound(address marketKey);
    error InvalidMorphoVault(uint16 vaultId);
    error InvalidMarketToken(address input, address token);
    error InvalidVaultAsset(address input, address token);

    constructor(address _morphoPool) {
        owner = msg.sender;
        morphoPool = IMorpho(_morphoPool);
    }

    modifier OnlyOwner() {
        if (msg.sender != owner) {
            revert NotOwner(msg.sender, owner);
        }
        _;
    }

    function updateOwner(address _newOwner) external OnlyOwner {
        emit UpdatedOwner(owner, _newOwner);
        owner = _newOwner;
    }

    function addMorphoMarket(address _market, bytes32 _marketId) external OnlyOwner {
        morphoMarket[_market] = _marketId;
        emit MorphoMarketAdded(_market, _marketId);
    }

    function addMorphoVault(address _vaultId, address _vaultAddress) external OnlyOwner {
        morphoVaults[_vaultId] = _vaultAddress;
        emit MorphoVaultAdded(_vaultId, _vaultAddress);
    }

    function rescueFunds(address _token, uint256 _amount) external OnlyOwner {
        IERC20(_token).transfer(owner, _amount);
    }

    function evaluateCondition(
        uint16,
        address _platformAddress,
        address _borrower,
        uint16 _parameter,
        uint256 _conditionValue
    ) external view returns (bool) {
        bytes32 marketId = morphoMarket[_platformAddress];
        if (marketId == bytes32(0)) {
            revert MorphoMarketNotFound(_platformAddress);
        }

        MarketParams memory market = morphoPool.idToMarketParams(Id.wrap(marketId));

        IOracle oracle = IOracle(market.oracle);

        uint256 price = oracle.price();

        Position memory position = morphoPool.position(Id.wrap(marketId), _borrower);

        Market memory marketData = morphoPool.market(Id.wrap(marketId));

        uint256 elapsed = block.timestamp - marketData.lastUpdate;

        // Skipped if elapsed == 0 or totalBorrowAssets == 0 because interest would be null, or if irm == address(0).
        if (elapsed != 0 && marketData.totalBorrowAssets != 0 && market.irm != address(0)) {
            uint256 borrowRate = IIrm(market.irm).borrowRateView(market, marketData);
            uint256 interest = marketData.totalBorrowAssets.wMulDown(borrowRate.wTaylorCompounded(elapsed));
            marketData.totalBorrowAssets += interest.toUint128();
            marketData.totalSupplyAssets += interest.toUint128();

            if (marketData.fee != 0) {
                uint256 feeAmount = interest.wMulDown(marketData.fee);
                // The fee amount is subtracted from the total supply in this calculation to compensate for the fact
                // that total supply is already updated.
                uint256 feeShares =
                    feeAmount.toSharesDown(marketData.totalSupplyAssets - feeAmount, marketData.totalSupplyShares);
                marketData.totalSupplyShares += feeShares.toUint128();
            }
        }

        uint8 decimals = 34 + IERC20(market.loanToken).decimals() - IERC20(market.collateralToken).decimals();

        price = price / 10 ** decimals;

        uint256 borrowed =
            uint256(position.borrowShares).toAssetsUp(marketData.totalBorrowAssets, marketData.totalBorrowShares);

        // Greater than asset Price
        if (_parameter == 0) {
            return price > _conditionValue;
        } // Less than or equal to asset Price
        else if (_parameter == 1) {
            return price <= _conditionValue;
        } else if (_parameter == 2) {
            return borrowed > _conditionValue;
        } // Less than or equal to debt balance
        else if (_parameter == 3) {
            return borrowed <= _conditionValue;
        }

        return false;
    }

    function getDepositToken(address, uint16 _assetType) external view returns (address) {
        return morphoVaults[convertToDepositAddress(_assetType)];
    }

    function unWindPosition(address, uint16 assetType, uint256 amount, address handler) external returns (uint256) {
        address vaultAddress = morphoVaults[convertToDepositAddress(assetType)];
        return IMetaMorpho(vaultAddress).redeem(amount, address(handler), address(this));
    }

    function handleDeposit(address token, uint256 amount, address _owner, bool repay, uint16 _platform) external {
        // Deposit into Morpho vaults
        if (_platform >= 2 && _platform <= 1002) {
            address vaultAddress = morphoVaults[convertToDepositAddress(_platform)];
            if (vaultAddress == address(0)) {
                revert InvalidMorphoVault(_platform);
            } else {
                address baseAsset = IMetaMorpho(vaultAddress).asset();

                if (token != baseAsset) {
                    revert InvalidVaultAsset(token, baseAsset);
                } else {
                    IERC20(token).approve(vaultAddress, amount);
                    IMetaMorpho(vaultAddress).deposit(amount, _owner);
                }
            }
        }

        //
        if (_platform >= 1003 && _platform <= 2003) {
            // Supply collateral or repay loans in morpho Markets
            bytes32 marketId = morphoMarket[convertToDepositAddress(_platform)];

            if (marketId == bytes32(0)) {
                revert MorphoMarketNotFound(convertToDepositAddress(_platform));
            } else {
                MarketParams memory market = morphoPool.idToMarketParams(Id.wrap(marketId));
                // Repay s
                if (repay && token == market.loanToken) {
                    Position memory position = morphoPool.position(Id.wrap(marketId), _owner);

                    Market memory marketData = morphoPool.market(Id.wrap(marketId));

                    // Updating Market Data
                    uint256 elapsed = block.timestamp - marketData.lastUpdate;

                    // Skipped if elapsed == 0 or totalBorrowAssets == 0 because interest would be null, or if irm == address(0).
                    if (elapsed != 0 && marketData.totalBorrowAssets != 0 && market.irm != address(0)) {
                        uint256 borrowRate = IIrm(market.irm).borrowRateView(market, marketData);
                        uint256 interest = marketData.totalBorrowAssets.wMulDown(borrowRate.wTaylorCompounded(elapsed));
                        marketData.totalBorrowAssets += interest.toUint128();
                        marketData.totalSupplyAssets += interest.toUint128();

                        if (marketData.fee != 0) {
                            uint256 feeAmount = interest.wMulDown(marketData.fee);
                            // The fee amount is subtracted from the total supply in this calculation to compensate for the fact
                            // that total supply is already updated.
                            uint256 feeShares = feeAmount.toSharesDown(
                                marketData.totalSupplyAssets - feeAmount, marketData.totalSupplyShares
                            );
                            marketData.totalSupplyShares += feeShares.toUint128();
                        }
                    }

                    uint256 borrowed = uint256(position.borrowShares).toAssetsUp(
                        marketData.totalBorrowAssets, marketData.totalBorrowShares
                    );

                    uint256 repayValue = amount;
                    if (amount > borrowed) {
                        repayValue = borrowed;
                        IERC20(token).transfer(_owner, amount - borrowed);
                    }

                    morphoPool.repay(
                        market,
                        repayValue, // Amount of assets to repay
                        0, // Use 0 for shares when specifying assets
                        address(owner), // Repay on behalf of this contract
                        "" // No callback data needed
                    );
                } else if (!repay && token == market.collateralToken) {
                    IERC20(token).approve(address(morphoPool), amount);
                    morphoPool.supplyCollateral(market, amount, _owner, "");
                } else {
                    revert InvalidMarketToken(token, market.collateralToken);
                }
            }
        }
    }

    function convertToDepositAddress(uint16 input) public pure returns (address) {
        return address(uint160(uint256(input)));
    }
}
