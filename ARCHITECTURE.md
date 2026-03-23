# Gated Trade Rebate Hook Architecture

## Flow Diagram

```
Trader (User)
    ↓
GatedTradeRebateRouter (Custom Wrapper)
    ↓ (automatically adds trader address to hookData)
V4SwapRouter (Standard Router)
    ↓
PoolManager.unlock()
    ↓
Router.unlockCallback()
    ↓
PoolManager.swap(poolKey, params, hookData)
    ↓
Hook.beforeSwap(sender, poolKey, params, hookData)
    ↓ (extracts trader address from hookData)
RebateAccessNFT.hasRebateAccessNFT(trader)
    ↓
✅ Swap proceeds OR ❌ Reverts with GatedTradeRebateRequired
```

## Component Roles

### GatedTradeRebateRouter
- **Purpose**: Wrapper around standard V4 router
- **Function**: Automatically encodes `msg.sender` (trader) into `hookData`
- **Benefit**: Users don't need to manually pass their address

### V4SwapRouter (Standard Router)
- **Purpose**: Standard Uniswap v4 router
- **Function**: Handles token transfers and calls PoolManager
- **Note**: Passes `hookData` through unchanged to PoolManager

### PoolManager
- **Purpose**: Core Uniswap v4 pool manager
- **Function**: Executes swaps and calls hooks
- **Note**: Passes `hookData` to hook's `beforeSwap` function

### GatedTradeRebateHook
- **Purpose**: Gated access verification hook
- **Function**: 
  1. Extracts trader address from `hookData`
  2. Checks if trader owns Rebate Access NFT
  3. Reverts if no NFT, allows swap if NFT exists

## Why GatedTradeRebateRouter is Needed

**Problem**: The `sender` parameter in `beforeSwap` is the router address, not the trader address.

**Solution**: GatedTradeRebateRouter automatically encodes the trader's address (`msg.sender`) into `hookData`, which the hook can then extract.

**Alternative**: Users could call the standard router directly and manually encode their address in `hookData`, but GatedTradeRebateRouter makes it transparent and user-friendly.

## Example Usage

```solidity
// User calls GatedTradeRebateRouter (simple - no hookData needed)
gatedTradeRebateRouter.swapExactTokensForTokens(
    amountIn,
    amountOutMin,
    zeroForOne,
    poolKey,
    receiver,  // No hookData parameter!
    deadline
);

// Internally, GatedTradeRebateRouter does:
bytes memory hookData = abi.encode(msg.sender); // Auto-encode trader
router.swapExactTokensForTokens(..., hookData, ...); // Forward to standard router
```

## Without GatedTradeRebateRouter

```solidity
// User would need to manually encode their address
bytes memory hookData = abi.encode(msg.sender);
router.swapExactTokensForTokens(..., hookData, ...);
```

This works, but GatedTradeRebateRouter makes it cleaner and less error-prone.
