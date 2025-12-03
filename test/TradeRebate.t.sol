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
import {DeepAmmMock} from "../src/DeepAmmMock.sol";
import {Bank} from "../src/Bank.sol";
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

    Bank bank;
    DeepAmmMock deepAmm;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // Deploys all required artifacts.
        deployArtifactsAndLabel();

        (currency0, currency1) = deployCurrencyPair();

        // Deploy bank and deep AMM
        bank = new Bank(0); // 0 bps fee for simple repay in tests
        deepAmm = new DeepAmmMock();

        // Deploy the hook to an address with the correct flags
        address flags =
            address(uint160(Hooks.BEFORE_SWAP_FLAG | Hooks.AFTER_SWAP_FLAG) ^ (0x4444 << 144)); // namespace
        // Construct args expected by TradeRebate(IPoolManager, IBank, IDeepAmmMock, IERC20 _weth, IERC20 _usdc, uint256)
        // Use the mocks and the test pair tokens; maxFlashAmount arbitrary
        bytes memory constructorArgs = abi.encode(
            poolManager,
            address(bank), // IBank
            address(deepAmm), // IDeepAmmMock
            Currency.unwrap(currency0), // WETH placeholder
            Currency.unwrap(currency1), // USDC placeholder
            uint256(1e6) // maxFlashAmount
        );
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

        // Prefund bank and deep AMM with USDC (currency1)
        address usdcAddr = Currency.unwrap(currency1);
        IERC20(usdcAddr).transfer(address(bank), 1_000_000e18);
        IERC20(usdcAddr).transfer(address(deepAmm), 1_000_000e18);
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

    function testSwapWithRebate_RepaysBank() public {
        // opt-in
        bytes memory hookData = abi.encode(address(this), true);
        uint256 amountIn = 1e18;

        // Perform swap
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: hookData,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        // With 0 bps fee, bank balance should be unchanged after borrow+repay
        address usdcAddr = Currency.unwrap(currency1);
        uint256 bankBal = IERC20(usdcAddr).balanceOf(address(bank));
        assertEq(bankBal, 1_000_000e18, "bank balance changed unexpectedly");
    }
}
