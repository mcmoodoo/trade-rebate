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

import {KYCHook} from "../src/KYCHook.sol";
import {BarterNFT} from "../src/BarterNFT.sol";
import {BaseTest} from "./utils/BaseTest.sol";

contract KYCHookTest is BaseTest {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    Currency currency0;
    Currency currency1;

    PoolKey poolKey;

    KYCHook hook;
    PoolId poolId;
    BarterNFT barterNFT;

    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // Deploys all required artifacts.
        deployArtifactsAndLabel();

        (currency0, currency1) = deployCurrencyPair();

        // Deploy BarterNFT first
        barterNFT = new BarterNFT();

        // Deploy the hook to an address with the correct flags
        address flags =
            address(uint160(Hooks.BEFORE_SWAP_FLAG) ^ (0x4444 << 144)); // namespace
        // Construct args expected by KYCHook(IPoolManager, IBarterNFT)
        bytes memory constructorArgs = abi.encode(poolManager, barterNFT);
        deployCodeTo("KYCHook.sol:KYCHook", constructorArgs, flags);
        hook = KYCHook(flags);

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

    function testKYCSucceedsWithNFT() public {
        // Verify trader doesn't have NFT initially
        assertFalse(barterNFT.hasBarterNFT(address(this)), "Trader should not have NFT initially");
        
        // Mint Barter NFT to this test contract (the trader)
        barterNFT.mint(address(this));
        
        // Verify trader now has NFT
        assertTrue(barterNFT.hasBarterNFT(address(this)), "Trader should have NFT after minting");
        
        // Perform a swap with trader address in hookData - should succeed because trader has NFT
        uint256 amountIn = 1e18;
        bytes memory hookData = abi.encode(address(this)); // Pass trader address
        BalanceDelta swapDelta = swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0, // Very bad, but we want to allow for unlimited price impact
            zeroForOne: true,
            poolKey: poolKey,
            hookData: hookData,
            receiver: address(this),
            deadline: block.timestamp + 1
        });

        // Verify swap succeeded (KYC check passed)
        assertEq(int256(swapDelta.amount0()), -int256(amountIn), "Swap should succeed when trader has NFT");
    }
    
    function testKYCFailsWithoutNFT() public {
        // Verify the trader doesn't have NFT
        assertFalse(barterNFT.hasBarterNFT(address(this)), "Trader should not have NFT");
        
        // Don't mint NFT - swap should fail with KYCRequired error
        uint256 amountIn = 1e18;
        bytes memory hookData = abi.encode(address(this));
        
        // Swap should revert because trader doesn't have NFT
        vm.expectRevert();
        swapRouter.swapExactTokensForTokens({
            amountIn: amountIn,
            amountOutMin: 0,
            zeroForOne: true,
            poolKey: poolKey,
            hookData: hookData,
            receiver: address(this),
            deadline: block.timestamp + 1
        });
    }
}
