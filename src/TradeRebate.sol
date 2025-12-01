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

interface IAavePool {
    function flashLoanSimple(
        address receiverAddress,
        address asset,
        uint256 amount,
        bytes calldata params,
        uint16 referralCode
    ) external;
}

interface IDeepAmmMock {
    function swapExact(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut);
}

interface IWETH {
    function deposit() external payable;
    function approve(address spender, uint256 amount) external returns (bool);
}

contract TradeRebate is BaseHook {
    using PoolIdLibrary for PoolKey;
    using StateLibrary for IPoolManager;

    // Reentrancy guard to prevent nested behavior in our own hooks
    bool private inHook;

    // Snapshot of pre-swap tick per pool
    mapping(PoolId => int24) private preSwapTick;

    // Config
    IAavePool public immutable aavePool;
    IDeepAmmMock public immutable deepAmm;
    IERC20 public immutable tokenUSDC;
    IERC20 public immutable tokenWETH;
    uint256 public immutable maxFlashAmount; // cap per attempt (asset units)

    // Profit ledger per ERC20
    mapping(address => uint256) public surplusByToken;

    event FlashArbExecuted(address asset, uint256 amount, uint256 premium, uint256 profit);

    constructor(
        IPoolManager _poolManager,
        IAavePool _aavePool,
        IDeepAmmMock _deepAmm,
        IERC20 _weth,
        IERC20 _usdc,
        uint256 _maxFlashAmount
    )
        BaseHook(_poolManager)
    {
        aavePool = _aavePool;
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
            // Encode pool leg params for callback
            bytes memory params = abi.encode(key, amount);
            // Borrow USDC; arbitrage via pool + deep AMM; repay; keep surplus in USDC
            aavePool.flashLoanSimple(address(this), address(tokenUSDC), amount, params, 0);
        }

        inHook = false;
        return (BaseHook.afterSwap.selector, 0);
    }

    // Aave v3 flash loan callback
    function executeOperation(
        address asset,
        uint256 amount,
        uint256 premium,
        address,
        bytes calldata params
    ) external returns (bool) {
        require(msg.sender == address(aavePool), "not Aave");
        require(asset == address(tokenUSDC), "asset mismatch");

        // Decode pool leg params
        (PoolKey memory key, uint256 poolAmountInUSDC) = abi.decode(params, (PoolKey, uint256));

        // 1) Execute pool leg: swap USDC -> ETH on the attached pool
        // Guard our own hooks from nested behavior
        bool prevInHook = inHook;
        inHook = true;
        {
            SwapParams memory sp = SwapParams({
                zeroForOne: false, // token1 (USDC) -> token0 (ETH)
                amountSpecified: int256(poolAmountInUSDC),
                sqrtPriceLimitX96: 0
            });
            // Perform swap; returns BalanceDelta (amount0, amount1) relative to caller (this hook)
            BalanceDelta d = poolManager.swap(key, sp, bytes(""));

            int128 delta0 = d.amount0(); // ETH delta
            int128 delta1 = d.amount1(); // USDC delta

            // If we owe USDC (negative), pay it: transfer USDC to PoolManager, sync, settle
            if (delta1 < 0) {
                uint256 oweUSDC = uint128(uint256(int256(-delta1)));
                tokenUSDC.transfer(address(poolManager), oweUSDC);
                poolManager.sync(key.currency1);
                poolManager.settle();
            }
            // If we are owed ETH (positive), take it and wrap to WETH
            if (delta0 > 0) {
                uint256 ethOut = uint128(uint256(int256(delta0)));
                poolManager.take(key.currency0, address(this), ethOut);
                // wrap to WETH
                IWETH(address(tokenWETH)).deposit{value: ethOut}();
            }
        }
        inHook = prevInHook;

        // 2) Trade on deep AMM mock: WETH -> USDC to realize profit (we already used USDC on pool leg)
        uint256 wethBal = tokenWETH.balanceOf(address(this));
        if (wethBal > 0) {
            tokenWETH.approve(address(deepAmm), wethBal);
            deepAmm.swapExact(address(tokenWETH), address(tokenUSDC), wethBal);
        }

        uint256 usdcBack = tokenUSDC.balanceOf(address(this));

        uint256 repay = amount + premium;
        require(usdcBack >= repay, "no profit");

        // 3) Repay Aave
        tokenUSDC.approve(address(aavePool), repay);

        // 4) Record surplus
        uint256 profit = usdcBack - repay;
        surplusByToken[address(tokenUSDC)] += profit;

        emit FlashArbExecuted(asset, amount, premium, profit);
        return true;
    }

    function _abs(int256 x) private pure returns (int256) {
        return x >= 0 ? x : -x;
    }
}

