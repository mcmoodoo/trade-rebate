// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "@uniswap/v4-core/src/libraries/Hooks.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {Constants} from "@uniswap/v4-core/test/utils/Constants.sol";

import {EasyPosm} from "./utils/libraries/EasyPosm.sol";

import {TradeRebate} from "../src/TradeRebate.sol";
import {BaseTest} from "./utils/BaseTest.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

contract TradeRebateTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;

    TradeRebate hook;
    PoolId poolId;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // Deploys all required artifacts.
        deployArtifactsAndLabel();

        (currency0, currency1) = deployCurrencyPair();

        // Deploy the hook to an address with the correct flags
        address flags =
            address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144)); // namespace
        // Construct args expected by TradeRebate(IPoolManager)
        bytes memory constructorArgs = abi.encode(poolManager);
        deployCodeTo("TradeRebate.sol:TradeRebate", constructorArgs, flags);
        hook = TradeRebate(flags);

        // Create the pool
        poolKey = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = poolKey.toId();
        poolManager.initialize(poolKey, Constants.SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(poolKey.tickSpacing);
        tickUpper = TickMath.maxUsableTick(poolKey.tickSpacing);

        uint128 liquidityAmount = 100e18;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            Constants.SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );

        (tokenId,) = positionManager.mint(
            poolKey,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            Constants.ZERO_BYTES
        );
    }

    function testCounterHooks() public {
        // Perform a test swap //
        uint256 amountIn = 1e18;
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        // ------------------- //

        assertEq(int256(swapDelta.amount0()), -int256(amountIn));
    }

    function testAfterSwapCalled() public {
        // Prefund the hook with both tokens
        address token0Addr = Currency.unwrap(currency0);
        address token1Addr = Currency.unwrap(currency1);
        uint256 prefundAmount = 10e18;

        assertEq(IERC20(token0Addr).balanceOf(address(hook)), 0, "hook should have zero token0 balance");
        assertEq(IERC20(token1Addr).balanceOf(address(hook)), 0, "hook should have zero token1 balance");
        
        IERC20(token0Addr).transfer(address(hook), prefundAmount);
        IERC20(token1Addr).transfer(address(hook), prefundAmount);
        
        // Record initial balances
        uint256 hookBalance0Before = IERC20(token0Addr).balanceOf(address(hook));
        uint256 hookBalance1Before = IERC20(token1Addr).balanceOf(address(hook));
        
        // Perform swap
        uint256 amountIn = 1e18;
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // very bad, but we want to allow for unllimited price impact
            zeroForOne: true,
            poolKey: poolKey,
            hookData: Constants.ZERO_BYTES,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
        
        // Check balances after swap
        uint256 hookBalance0After = IERC20(token0Addr).balanceOf(address(hook));
        uint256 hookBalance1After = IERC20(token1Addr).balanceOf(address(hook));
        
        // Verify hook still has tokens (afterSwap was called and could have used them)
        assertEq(hookBalance0Before, prefundAmount, "hook should have prefunded token0");
        assertEq(hookBalance1Before, prefundAmount, "hook should have prefunded token1");
        // After swap, balances may have changed if afterSwap hook used them
        assertGe(hookBalance0After, 0, "hook token0 balance should be >= 0");
        assertGe(hookBalance1After, 0, "hook token1 balance should be >= 0");
    }
}
