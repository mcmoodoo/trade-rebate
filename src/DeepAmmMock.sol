// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IERC20} from "forge-std/interfaces/IERC20.sol";

/// @notice Extremely simple mock of a deep-liquidity AMM that returns a fixed positive edge
/// on a two-leg path (tokenIn -> tokenMid -> tokenOut). It requires the contract to be pre-funded
/// with sufficient balances of both tokens to honor payouts.
import {IDeepAmmMock} from "./TradeRebate.sol";

contract DeepAmmMock is IDeepAmmMock {
    address public immutable owner;
    // profitBps is applied on tokenOut amount (e.g., 10 = +0.1%)
    uint256 public profitBps = 10;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    function setProfitBps(uint256 bps) external onlyOwner {
        require(bps <= 10_000, "bps>100%");
        profitBps = bps;
    }

    /// @dev Swaps tokenIn to tokenOut with a small positive edge for the caller.
    function swapExact(address tokenIn, address tokenOut, uint256 amountIn) external returns (uint256 amountOut) {
        require(tokenIn != tokenOut, "same token");
        require(amountIn > 0, "amount=0");
        IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
        // 1:1 plus profitBps edge
        amountOut = amountIn + (amountIn * profitBps) / 10_000;
        IERC20(tokenOut).transfer(msg.sender, amountOut);
    }
}

