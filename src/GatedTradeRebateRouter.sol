// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {PathKey} from "hookmate/interfaces/router/PathKey.sol";
import {IUniswapV4Router04} from "hookmate/interfaces/router/IUniswapV4Router04.sol";

/// @notice Custom router wrapper that automatically passes trader address to hooks via hookData
/// @dev This router wraps the standard V4 router and automatically encodes msg.sender into hookData
contract GatedTradeRebateRouter {
    IUniswapV4Router04 public immutable router;

    constructor(IUniswapV4Router04 _router) {
        router = _router;
    }

    /// @notice Single pool, exact input swap with automatic trader address encoding
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        bool zeroForOne,
        PoolKey calldata poolKey,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta) {
        // Automatically encode msg.sender (trader) into hookData
        bytes memory hookData = abi.encode(msg.sender);
        
        return router.swapExactTokensForTokens(
            amountIn,
            amountOutMin,
            zeroForOne,
            poolKey,
            hookData,
            receiver,
            deadline
        );
    }

    /// @notice Single pool, exact output swap with automatic trader address encoding
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        bool zeroForOne,
        PoolKey calldata poolKey,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta) {
        // Automatically encode msg.sender (trader) into hookData
        bytes memory hookData = abi.encode(msg.sender);
        
        return router.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            zeroForOne,
            poolKey,
            hookData,
            receiver,
            deadline
        );
    }

    /// @notice Multi-pool exact input swap with automatic trader address encoding
    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        Currency startCurrency,
        PathKey[] calldata path,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta) {
        // For multi-pool swaps, we need to encode trader address for each pool
        // Since PathKey contains hookData, we need to modify the path
        // For simplicity, this implementation assumes single-pool swaps
        // Multi-pool support would require modifying PathKey array
        revert("Multi-pool swaps not yet supported");
    }

    /// @notice Multi-pool exact output swap with automatic trader address encoding
    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        Currency startCurrency,
        PathKey[] calldata path,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta) {
        revert("Multi-pool swaps not yet supported");
    }

    /// @notice General-purpose swap with automatic trader address encoding
    function swap(
        int256 amountSpecified,
        uint256 amountLimit,
        Currency startCurrency,
        PathKey[] calldata path,
        address receiver,
        uint256 deadline
    ) external payable returns (BalanceDelta) {
        revert("Multi-pool swaps not yet supported");
    }
}
