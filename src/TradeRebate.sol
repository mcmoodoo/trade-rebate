// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract TradeRebate is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;
    using CurrencyLibrary for Currency;

    // Reentrancy guard to prevent nested behavior in our own hooks
    bool private inHook;

    event afterSwapCalled(address);

    // Snapshot of pre-swap tick per pool
    mapping(PoolId => int24) private preSwapTick;

    constructor(IPoolManager _poolManager) BaseHook(_poolManager) {}

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeSwap(address, PoolKey calldata key, SwapParams calldata, bytes calldata)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Snapshot current tick for later spill estimation
        (uint160 sqrtBefore, int24 tick, uint24 pf0, uint24 lf0) = poolManager.getSlot0(key.toId());
        preSwapTick[key.toId()] = tick;
        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }

    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata)
        internal
        override
        returns (bytes4, int128)
    {
        emit afterSwapCalled(msg.sender);
        // if (inHook) {
        //     // prevent nested behavior if our actions (if any in future) re-trigger hooks
        //     return (BaseHook.afterSwap.selector, 0);
        // }
        // inHook = true;

        // Perform a small swap: token0 -> token1 if hook has token0 balance
        address token0Addr = Currency.unwrap(key.currency0);
        uint256 token0Balance = IERC20(token0Addr).balanceOf(address(this));
        
        if (token0Balance > 0) {
            // Swap a small amount (10% of balance, or minimum 1e15)
            uint256 swapAmount = token0Balance / 10;
            if (swapAmount < 1e15) {
                swapAmount = token0Balance; // Use all if balance is very small
            }
            
            // Perform swap: token0 -> token1 (zeroForOne = true)
            SwapParams memory swapParams = SwapParams({
                zeroForOne: true,
                amountSpecified: -int256(swapAmount), // negative = exact input
                sqrtPriceLimitX96: 0 // no price limit
            });
            
            BalanceDelta delta = poolManager.swap(key, swapParams, bytes(""));
            
            // Handle balance deltas
            int128 delta0 = delta.amount0(); // token0 delta
            int128 delta1 = delta.amount1(); // token1 delta
            
            // If we owe token0, transfer and settle
            if (delta0 < 0) {
                uint256 oweToken0 = uint128(uint256(int256(-delta0)));
                IERC20(token0Addr).transfer(address(poolManager), oweToken0);
                poolManager.settle();
            }
            
            // If we're owed token1, take it
            if (delta1 > 0) {
                uint256 receiveToken1 = uint128(uint256(int256(delta1)));
                poolManager.take(key.currency1, address(this), receiveToken1);
            }
        }

        inHook = false;
        return (BaseHook.afterSwap.selector, 0);
    }
}

