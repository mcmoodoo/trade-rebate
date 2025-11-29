// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SequenceBase} from "./SequenceBase.sol";

import {IERC20} from "forge-std/interfaces/IERC20.sol";

import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "@uniswap/v4-core/src/types/PoolId.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";
import {TickMath} from "@uniswap/v4-core/src/libraries/TickMath.sol";
import {LiquidityAmounts} from "@uniswap/v4-core/test/utils/LiquidityAmounts.sol";
import {Actions} from "@uniswap/v4-periphery/src/libraries/Actions.sol";
import {IPositionManager} from "@uniswap/v4-periphery/src/interfaces/IPositionManager.sol";
import {IPermit2} from "permit2/src/interfaces/IPermit2.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";

/// @notice Adds initial liquidity to the created pool using stored deployments.
contract AddLiquidityFromJson is SequenceBase {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    // Configure nominal deposit amounts for each token (raw units)
    // Assuming fUSDC(6) and fWBTC(8); adjust as needed.
    uint256 public constant FUSDC_AMOUNT = 100_000_000; // 100 fUSDC (6 decimals)
    uint256 public constant FWBTC_AMOUNT = 10_000_000;  // 0.1 fWBTC (8 decimals)

    function run() external {
        Deployments memory d = _readDeployments();
        require(d.poolManager != address(0) && d.positionManager != address(0), "V4 infra not deployed");
        require(d.token0 != address(0) && d.token1 != address(0), "Tokens not deployed");
        require(d.lpFee != 0 && d.tickSpacing != 0, "Pool config not set");

        // Build PoolKey based on sorted currencies (must match pool initialization)
        Currency a = Currency.wrap(d.token0);
        Currency b = Currency.wrap(d.token1);
        (Currency c0, Currency c1) = a < b ? (a, b) : (b, a);

        PoolKey memory poolKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: uint24(d.lpFee),
            tickSpacing: int24(d.tickSpacing),
            hooks: IHooks(d.hook) // must match the pool's hook to compute same PoolId
        });

        // Align deposit amounts with currency order
        bool token0IsC0 = (a < b);
        uint256 amount0Desired = token0IsC0 ? FUSDC_AMOUNT : FWBTC_AMOUNT;
        uint256 amount1Desired = token0IsC0 ? FWBTC_AMOUNT : FUSDC_AMOUNT;

        // Read current pool price
        (uint160 sqrtPriceX96,,,) = IPoolManager(d.poolManager).getSlot0(poolKey.toId());
        int24 currentTick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        int24 tickSpacing = int24(d.tickSpacing);
        int24 tickLower = ((currentTick - 1000 * tickSpacing) / tickSpacing) * tickSpacing;
        int24 tickUpper = ((currentTick + 1000 * tickSpacing) / tickSpacing) * tickSpacing;

        // Compute liquidity from desired token amounts
        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0Desired,
            amount1Desired
        );

        // Slippage caps (tiny buffer)
        uint256 amount0Max = amount0Desired + 1;
        uint256 amount1Max = amount1Desired + 1;

        // Prepare actions and params for PositionManager.modifyLiquidities
        bytes memory actions = abi.encodePacked(
            uint8(Actions.MINT_POSITION),
            uint8(Actions.SETTLE_PAIR),
            uint8(Actions.SWEEP),
            uint8(Actions.SWEEP)
        );

        bytes[] memory params = new bytes[](4);
        params[0] = abi.encode(
            poolKey, tickLower, tickUpper, liquidity, amount0Max, amount1Max, msg.sender, new bytes(0)
        );
        params[1] = abi.encode(poolKey.currency0, poolKey.currency1);
        params[2] = abi.encode(poolKey.currency0, msg.sender);
        params[3] = abi.encode(poolKey.currency1, msg.sender);

        vm.startBroadcast();
        // Approvals via Permit2 (must be broadcast by the EOA supplying funds)
        IERC20(d.token0).approve(d.permit2, type(uint256).max);
        IERC20(d.token1).approve(d.permit2, type(uint256).max);
        IPermit2(d.permit2).approve(d.token0, d.positionManager, type(uint160).max, type(uint48).max);
        IPermit2(d.permit2).approve(d.token1, d.positionManager, type(uint160).max, type(uint48).max);
        IPositionManager(d.positionManager).modifyLiquidities(
            abi.encode(actions, params),
            block.timestamp + 600
        );
        vm.stopBroadcast();
    }
}

