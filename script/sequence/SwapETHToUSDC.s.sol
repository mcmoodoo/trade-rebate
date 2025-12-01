// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {SequenceBase} from "./SequenceBase.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "@uniswap/v4-core/src/types/Currency.sol";

import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";
import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @notice Swaps ETH -> USDC using router and pool config from deployments.json
/// @dev Expects deployments.json to have: token0, token1, lpFee, tickSpacing, hook, router.
///      If neither side is native ETH (address(0)), it will attempt ERC20->ERC20 by approving the router.
contract SwapETHToUSDC_FromJson is SequenceBase {
    function run() external {
        Deployments memory d = _readDeployments();
        require(d.router != address(0), "Router not set");
        require(d.lpFee != 0 && d.tickSpacing != 0, "Pool config missing");
        require(d.token0 != d.token1, "Invalid token pair");

        // Sort currencies per v4 requirements
        Currency a = Currency.wrap(d.token0);
        Currency b = Currency.wrap(d.token1);
        (Currency c0, Currency c1) = a < b ? (a, b) : (b, a);

        PoolKey memory poolKey = PoolKey({
            currency0: c0,
            currency1: c1,
            fee: uint24(d.lpFee),
            tickSpacing: int24(d.tickSpacing),
            hooks: IHooks(d.hook)
        });

        // Inputs (overridable via env)
        uint256 amountIn = vm.envOr("AMOUNT_IN_WEI", uint256(1e17)); // default 0.1 ETH
        uint256 amountOutMin = vm.envOr("AMOUNT_OUT_MIN", uint256(0));
        address receiver = vm.envOr("RECEIVER", tx.origin);

        // Determine direction: zeroForOne means currency0 -> currency1
        bool c0IsEth = Currency.unwrap(c0) == address(0);
        bool c1IsEth = Currency.unwrap(c1) == address(0);
        require(c0IsEth || c1IsEth, "No native ETH in pool");
        bool zeroForOne = c0IsEth; // ETH is currency0 => ETH -> USDC

        // Opt-in to self-arbitrage in the hook
        bytes memory hookData = abi.encode(receiver, true);

        IUniswapV4Router04 router = IUniswapV4Router04(payable(d.router));

        vm.startBroadcast();
        if (zeroForOne) {
            // ETH (native) -> USDC: send value along with the call
            router.swapExactTokensForTokens{value: amountIn}(
                amountIn,
                amountOutMin,
                true,
                poolKey,
                hookData,
                receiver,
                block.timestamp + 600
            );
        } else {
            // USDC -> ETH: approve router to pull ERC20 and receive native ETH
            address usdcLike = Currency.unwrap(c0); // if ETH is c1, then c0 is ERC20
            IERC20(usdcLike).approve(address(router), amountIn);
            router.swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                false,
                poolKey,
                hookData,
                receiver,
                block.timestamp + 600
            );
        }
        vm.stopBroadcast();
    }
}

