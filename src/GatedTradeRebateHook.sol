// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IBarterNFT} from "./IBarterNFT.sol";

/// @notice Gated Trade Rebate Hook that requires traders to own a Barter NFT before swapping
contract GatedTradeRebateHook is BaseHook {
    IBarterNFT public immutable barterNFT;

    error GatedTradeRebateRequired(address trader);

    constructor(IPoolManager _poolManager, IBarterNFT _barterNFT) BaseHook(_poolManager) {
        barterNFT = _barterNFT;
    }

    function getHookPermissions() public pure override returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: false,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: true,
            afterSwap: false,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }

    function _beforeSwap(address sender, PoolKey calldata, SwapParams calldata, bytes calldata hookData)
        internal
        override
        returns (bytes4, BeforeSwapDelta, uint24)
    {
        // Extract trader address from hookData (passed by custom router)
        address trader = sender; // Default to sender (router)
        if (hookData.length >= 20) {
            // If hookData contains an address, use it (from custom router)
            trader = abi.decode(hookData, (address));
        }

        // Gate check: verify trader has Barter NFT
        if (!barterNFT.hasBarterNFT(trader)) {
            revert GatedTradeRebateRequired(trader);
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
}
