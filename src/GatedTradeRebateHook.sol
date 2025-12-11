// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {BaseHook} from "@openzeppelin/uniswap-hooks/src/base/BaseHook.sol";

import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {IPoolManager, SwapParams} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "@uniswap/v4-core/src/types/BeforeSwapDelta.sol";
import {IRebateAccessNFT} from "./IRebateAccessNFT.sol";

/// @notice Gated Trade Rebate Hook that requires traders to own a Rebate Access NFT before swapping
contract GatedTradeRebateHook is BaseHook {
    IRebateAccessNFT public immutable rebateAccessNFT;

    error GatedTradeRebateRequired(address trader);

    constructor(IPoolManager _poolManager, IRebateAccessNFT _rebateAccessNFT) BaseHook(_poolManager) {
        rebateAccessNFT = _rebateAccessNFT;
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

        // Gate check: verify trader has Rebate Access NFT
        if (!rebateAccessNFT.hasRebateAccessNFT(trader)) {
            revert GatedTradeRebateRequired(trader);
        }

        return (BaseHook.beforeSwap.selector, BeforeSwapDeltaLibrary.ZERO_DELTA, 0);
    }
}
