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

// Simple helper to safely receive native ETH without reverting
contract PayableReceiver {
    receive() external payable {}
}

/// @notice Adds initial liquidity to the created pool using stored deployments.
contract AddLiquidity is SequenceBase {
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;
    using PoolIdLibrary for PoolKey;

    // Configure nominal deposit amounts for ETH and USDC
    // Defaults: 0.5 ETH and 1,000 USDC
    uint256 public constant ETH_AMOUNT_WEI = 0.5 ether;    // native ETH
    uint256 public constant USDC_AMOUNT = 1_000e6;         // 6 decimals

    function run() external {
        Deployments memory d = _readDeployments();
        require(d.poolManager != address(0) && d.positionManager != address(0), "V4 infra not deployed");
        // Allow native ETH (address(0)) for one side. Only ensure tokens are not identical.
        require(d.token0 != d.token1, "Invalid token addresses");
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

        // Align deposit amounts with currency order; handle native ETH
        bool token0IsC0 = (a < b);
        // Identify which side is native ETH
        bool c0IsEth = Currency.unwrap(c0) == address(0);
        bool c1IsEth = Currency.unwrap(c1) == address(0);
        // Set desired amounts by currency order
        uint256 amount0Desired = token0IsC0
            ? (Currency.unwrap(a) == address(0) ? ETH_AMOUNT_WEI : USDC_AMOUNT)
            : (Currency.unwrap(b) == address(0) ? ETH_AMOUNT_WEI : USDC_AMOUNT);
        uint256 amount1Desired = token0IsC0
            ? (Currency.unwrap(b) == address(0) ? ETH_AMOUNT_WEI : USDC_AMOUNT)
            : (Currency.unwrap(a) == address(0) ? ETH_AMOUNT_WEI : USDC_AMOUNT);

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

        // Compute the exact amounts that will be used for the computed liquidity.
        // This prevents overfunding and avoids sweeping large native ETH refunds,
        // which can revert when the recipient is a contract without a payable receive.
        (uint256 amount0Exact, uint256 amount1Exact) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidity
        );

        // Allow +1 unit headroom on both sides to accommodate rounding in engine.
        uint256 amount0Max = amount0Exact + 1;
        uint256 amount1Max = amount1Exact + 1;

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

        // Route native ETH refunds (if any) to a dedicated payable receiver to avoid reverts
        address payable ethRefundReceiver = payable(msg.sender);
        if (c0IsEth || c1IsEth) {
            ethRefundReceiver = payable(address(new PayableReceiver()));
        }
        params[2] = abi.encode(poolKey.currency0, c0IsEth ? ethRefundReceiver : payable(msg.sender));
        params[3] = abi.encode(poolKey.currency1, c1IsEth ? ethRefundReceiver : payable(msg.sender));

        // Determine ETH value to send if one side is native
        // Provide slight headroom (+1) for native ETH to avoid rounding shortfall;
        // any excess will be refunded to the payable receiver.
        uint256 ethValue = c0IsEth ? (amount0Exact + 1) : (c1IsEth ? (amount1Exact + 1) : 0);

        vm.startBroadcast();
        // Approvals via Permit2 for ERC20 side (must be broadcast by the EOA supplying funds)
        if (d.token0 != address(0)) {
            IERC20(d.token0).approve(d.permit2, type(uint256).max);
            IPermit2(d.permit2).approve(d.token0, d.positionManager, type(uint160).max, type(uint48).max);
        }
        if (d.token1 != address(0)) {
            IERC20(d.token1).approve(d.permit2, type(uint256).max);
            IPermit2(d.permit2).approve(d.token1, d.positionManager, type(uint160).max, type(uint48).max);
        }
        IPositionManager(d.positionManager).modifyLiquidities{value: ethValue}(
            abi.encode(actions, params),
            type(uint256).max
        );
        vm.stopBroadcast();
    }
}

