// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {console2} from "forge-std/Script.sol";
import {SequenceBase} from "./SequenceBase.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";

import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {PositionInfo, PositionInfoLibrary} from "@uniswap/v4-periphery/src/libraries/PositionInfoLibrary.sol";

/// @notice Describe pool state and list positions belonging to this pool.
contract DescribePool is SequenceBase {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    function run() external view {
        Deployments memory d = _readDeployments();
        require(d.poolManager != address(0) && d.positionManager != address(0), "Infra missing");
        require(d.lpFee != 0 && d.tickSpacing != 0, "Pool config missing");
        require(d.token0 != d.token1, "Invalid token pair");

        Currency a = Currency.wrap(d.token0);
        Currency b = Currency.wrap(d.token1);
        (Currency c0, Currency c1) = a < b ? (a, b) : (b, a);

        PoolKey memory poolKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: uint24(d.lpFee),
            tickSpacing: int24(d.tickSpacing),
            hooks: IHooks(d.hook)
        });
        PoolId poolId = poolKey.toId();

        // Slot0 (sqrtPriceX96, tick, fee, protocolFee not all printed)
        (uint160 sqrtPriceX96, int24 currentTick, uint24 protocolFee, uint24 swapFee) =
            IPoolManager(d.poolManager).getSlot0(poolId);

        console2.log("--- Pool State ---");
        console2.log("PoolManager    :", d.poolManager);
        console2.log("PositionManager:", d.positionManager);
        console2.log("Hook           :", d.hook);
        console2.log("currency0      :", Currency.unwrap(c0));
        console2.log("currency1      :", Currency.unwrap(c1));
        console2.log("fee            :", uint256(d.lpFee));
        console2.log("tickSpacing    :", int24(d.tickSpacing));
        console2.log("poolId         :");
        console2.logBytes32(PoolId.unwrap(poolId));
        console2.log("sqrtPriceX96   :", uint256(sqrtPriceX96));
        console2.log("currentTick    :", currentTick);
        console2.log("protocolFee    :", uint256(protocolFee));
        console2.log("swapFee        :", uint256(swapFee));

        // Note: Enumerating LP positions and owners on-chain is non-trivial without indexing.
        // This script focuses on core pool state. Use subgraphs or bespoke scripts to index positions.
    }
}

