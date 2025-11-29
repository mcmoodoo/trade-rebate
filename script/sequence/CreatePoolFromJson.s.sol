// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SequenceBase} from "./SequenceBase.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";

/// @notice Creates a pool using deployed infra and tokens; persists fee, tickSpacing, poolId.
contract CreatePoolFromJson is SequenceBase {
    using CurrencyLibrary for Currency;
    using PoolIdLibrary for PoolKey;

    // Configuration (kept constant for sequence)
    uint24 public constant LP_FEE = 3000; // 0.30%
    int24 public constant TICK_SPACING = 60;
    uint160 public constant STARTING_PRICE = 2 ** 96; // sqrtPriceX96 for price=1

    function run() external {
        Deployments memory d = _readDeployments();
        require(d.positionManager != address(0), "PositionManager not deployed");
        require(d.token0 != address(0) && d.token1 != address(0), "Tokens not deployed");

        // Sort currencies by address as required by v4
        Currency a = Currency.wrap(d.token0);
        Currency b = Currency.wrap(d.token1);
        (Currency c0, Currency c1) = a < b ? (a, b) : (b, a);

        PoolKey memory poolKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: LP_FEE,
            tickSpacing: TICK_SPACING,
            hooks: IHooks(d.hook) // address(0) if no hook
        });

        bytes memory hookData = new bytes(0);

        vm.startBroadcast();
        // Use multicall with encoded selector to support 3-arg initializePool
        IPositionManager pm = IPositionManager(d.positionManager);
        bytes[] memory calls = new bytes[](1);
        calls[0] = abi.encodeWithSelector(pm.initializePool.selector, poolKey, STARTING_PRICE, hookData);
        pm.multicall(calls);
        vm.stopBroadcast();

        // Persist config and computed pool id
        d.lpFee = LP_FEE;
        d.tickSpacing = TICK_SPACING;
        d.poolId = PoolId.unwrap(poolKey.toId());
        _writeDeployments(d);
    }
}

