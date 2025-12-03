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
import {IERC20} from "forge-std/interfaces/IERC20.sol";

interface IDeepAmmMock {
    function swapExact(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut);
}

interface IBank {
    function borrow(address token, uint256 amount) external;
    function feeBps() external view returns (uint256);
}

contract TradeRebate is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // Reentrancy guard to prevent nested behavior in our own hooks
    bool private inHook;

    // Snapshot of pre-swap tick per pool
    mapping(PoolId => int24) private preSwapTick;

    // Config
    IBank public immutable bank;
    IDeepAmmMock public immutable deepAmm;
    IERC20 public immutable tokenUSDC;
    IERC20 public immutable tokenWETH;
    uint256 public immutable maxFlashAmount; // cap per attempt (asset units)

    // Profit ledger per ERC20
    mapping(address => uint256) public surplusByToken;

    event ArbitrageExecuted(uint256 borrowed, uint256 feePaid, uint256 profit);

    constructor(
        IPoolManager _poolManager,
        IBank _bank,
        IDeepAmmMock _deepAmm,
        IERC20 _weth,
        IERC20 _usdc,
        uint256 _maxFlashAmount
    )
        BaseHook(_poolManager)
    {
        bank = _bank;
        deepAmm = _deepAmm;
        tokenWETH = _weth;
        tokenUSDC = _usdc;
        maxFlashAmount = _maxFlashAmount;
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

    // hookData encoding: abi.encode(address trader, bool enableAtomicAttempt)
    function _afterSwap(address, PoolKey calldata key, SwapParams calldata, BalanceDelta, bytes calldata hookData)
        internal
        override
        returns (bytes4, int128)
    {
        if (inHook) {
            // prevent nested behavior if our actions (if any in future) re-trigger hooks
            return (BaseHook.afterSwap.selector, 0);
        }
        inHook = true;

        // Read post-swap tick
        (uint160 sqrtAfter, int24 tickAfter, uint24 pf1, uint24 lf1) = poolManager.getSlot0(key.toId());
        int24 tickBefore = preSwapTick[key.toId()];

        // Parse enable flag (trader currently unused)
        bool enable = false;
        if (hookData.length >= 64) {
            (, enable) = abi.decode(hookData, (address, bool));
        }

        // Simple guard: attempt only if enabled and movement is non-trivial
        if (enable && _abs(tickAfter - tickBefore) > 0) {
            uint256 amount = maxFlashAmount;
            // Borrow USDC from the bank (trust-based)
            bank.borrow(address(tokenUSDC), amount);
            // Immediately repay principal + fee (no in-hook trading for simplicity)
            uint256 fee = (amount * bank.feeBps()) / 10_000;
            uint256 repay = amount + fee;
            tokenUSDC.transfer(address(bank), repay);
            emit ArbitrageExecuted(amount, fee, 0);
        }

        inHook = false;
        return (BaseHook.afterSwap.selector, 0);
    }

    function _abs(int256 x) private pure returns (int256) {
        return x >= 0 ? x : -x;
    }
}

