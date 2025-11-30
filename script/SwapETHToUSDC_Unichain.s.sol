// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Script} from "forge-std/Script.sol";

import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";

import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";

/// @notice Swaps 5 ETH -> USDC on Unichain via Uniswap v4 router
/// @dev Router is read from deployments.json ("router" field)
///      Optional envs:
///        - RECEIVER: address to receive USDC (defaults to tx.origin)
///        - AMOUNT_OUT_MIN: minimum USDC out (defaults to 0)
///        - FEE: pool fee in bps (defaults to 3000)
///        - TICK_SPACING: pool tick spacing (defaults to 60)
contract SwapETHToUSDC_Unichain is Script {
    // USDC on Unichain (provided)
    address internal constant USDC = 0x078D782b760474a361dDA0AF3839290b0EF57AD6;

    function run() external {
        // Load router from deployments.json
        string memory json = vm.readFile("deployments.json");
        address routerAddr = vm.parseJsonAddress(json, ".router");
        IUniswapV4Router04 V4_ROUTER = IUniswapV4Router04(payable(routerAddr));

        // Optional configuration
        uint256 amountOutMin = vm.envOr("AMOUNT_OUT_MIN", uint256(0));
        uint24 fee = uint24(vm.envOr("FEE", uint256(3000))); // 0.30%
        int24 tickSpacing = int24(uint24(vm.envOr("TICK_SPACING", uint256(60))));
        address receiver = vm.envOr("RECEIVER", tx.origin);

        // Single-pool ETH (native) -> USDC pool key (no hooks)
        // Note: Currency(address(0)) represents native ETH
        PoolKey memory poolKey = PoolKey({
            currency0: Currency.wrap(address(0)), // ETH (native)
            currency1: Currency.wrap(USDC),       // USDC
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(0))
        });

        // Exact input: 5 ETH
        uint256 amountIn = 20 ether;

        // No hook data for a standard pool
        bytes memory hookData = new bytes(0);

        vm.startBroadcast();

        // Perform the swap, sending 5 ETH as msg.value
        V4_ROUTER.swapExactTokensForTokens{value: amountIn}(
            amountIn,         // amountIn (ETH)
            amountOutMin,     // min USDC out
            true,             // zeroForOne: currency0 (ETH) -> currency1 (USDC)
            poolKey,          // single pool
            hookData,         // no hooks
            receiver,         // recipient of USDC
            block.timestamp + 15 minutes
        );

        vm.stopBroadcast();
    }
}

