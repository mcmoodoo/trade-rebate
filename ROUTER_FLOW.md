# How Router Calls PoolManager - Uniswap v4 Flow

## Overview
Uniswap v4 uses an **unlock pattern** to handle reentrancy and balance accounting. The router doesn't directly call `swap()` - instead it uses a callback pattern.

## Call Flow (from test trace)

```
1. swapRouter.swapExactTokensForTokens()
   ↓
2. poolManager.unlock(data)
   ↓
3. router.unlockCallback(data)  [callback]
   ↓
4. poolManager.swap(poolKey, params, hookData)
   ↓
5. hook.beforeSwap(...)  [if hook enabled]
   ↓
6. [Actual swap execution happens]
   ↓
7. hook.afterSwap(...)  [if hook enabled]
   ↓
8. Returns BalanceDelta to router
   ↓
9. Router handles token transfers
   ↓
10. poolManager.unlock() completes
```

## Code Snippets

### 1. Router Entry Point

```solidity
// In V4SwapRouter (simplified)
function swapExactTokensForTokens(
    uint256 amountIn,
    uint256 amountOutMin,
    bool zeroForOne,
    PoolKey calldata poolKey,
    bytes calldata hookData,
    address receiver,
    uint256 deadline
) external returns (BalanceDelta swapDelta) {
    // Transfer tokens from user to router
    IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn);
    
    // Call poolManager.unlock() - this will callback to unlockCallback
    swapDelta = poolManager.unlock(
        abi.encode(
            poolKey,
            SwapParams({zeroForOne: zeroForOne, amountSpecified: -int256(amountIn), sqrtPriceLimitX96: 0}),
            hookData,
            receiver
        )
    );
    
    // Handle output tokens
    // ...
}
```

### 2. PoolManager Unlock Pattern

```solidity
// In PoolManager (simplified)
function unlock(bytes calldata data) external returns (BalanceDelta delta) {
    // Set lock state
    locked = true;
    
    // Call back to the caller (router)
    delta = msg.sender.unlockCallback(data);
    
    // Settle all balances
    settleAllBalances();
    
    // Clear lock
    locked = false;
}
```

### 3. Router's Unlock Callback

```solidity
// In V4SwapRouter (simplified)
function unlockCallback(bytes calldata data) external returns (BalanceDelta) {
    require(msg.sender == address(poolManager), "Only poolManager");
    
    // Decode the swap parameters
    (PoolKey memory poolKey, SwapParams memory params, bytes memory hookData, address receiver) = 
        abi.decode(data, (PoolKey, SwapParams, bytes, address));
    
    // NOW we can call swap() - poolManager is unlocked for us
    BalanceDelta delta = poolManager.swap(poolKey, params, hookData);
    
    // Handle the balance deltas:
    // - If delta.amount0() < 0: we owe token0, transfer it
    // - If delta.amount1() > 0: we're owed token1, take it
    
    if (delta.amount0() < 0) {
        uint256 owe0 = uint256(uint128(-delta.amount0()));
        IERC20(poolKey.currency0).transfer(address(poolManager), owe0);
        poolManager.settle(poolKey.currency0);
    }
    
    if (delta.amount1() > 0) {
        uint256 receive1 = uint256(uint128(delta.amount1()));
        poolManager.take(poolKey.currency1, receiver, receive1);
    }
    
    return delta;
}
```

### 4. PoolManager Swap (calls hooks)

```solidity
// In PoolManager (simplified)
function swap(
    PoolKey calldata key,
    SwapParams calldata params,
    bytes calldata hookData
) external returns (BalanceDelta delta) {
    require(locked, "Must be in unlock");
    
    // Call beforeSwap hook if enabled
    if (hasHook(key.hooks, BEFORE_SWAP_FLAG)) {
        (bytes4 selector, BeforeSwapDelta beforeDelta, uint24 fee) = 
            key.hooks.beforeSwap(msg.sender, key, params, hookData);
        // Apply beforeDelta adjustments...
    }
    
    // Execute the actual swap
    delta = _executeSwap(key, params);
    
    // Call afterSwap hook if enabled
    if (hasHook(key.hooks, AFTER_SWAP_FLAG)) {
        int128 afterDelta = key.hooks.afterSwap(msg.sender, key, params, delta, hookData);
        // Apply afterDelta adjustments...
    }
    
    return delta;
}
```

## Why This Pattern?

1. **Reentrancy Protection**: The `locked` flag prevents reentrant calls
2. **Balance Accounting**: All balance changes happen within the unlock window
3. **Hook Safety**: Hooks can't call `swap()` again because poolManager is locked
4. **Gas Efficiency**: Single unlock call handles all balance settlements

## The Problem in Your Code

When you try to call `poolManager.swap()` from within `afterSwap`:

```solidity
function _afterSwap(...) internal override returns (bytes4, int128) {
    // ❌ This fails because poolManager is already locked!
    poolManager.swap(key, swapParams, bytes(""));
}
```

The poolManager is locked during the entire `unlock()` → `unlockCallback()` → `swap()` → `afterSwap()` flow, so you **cannot** call `swap()` again from within the hook.

## Solution Options

1. **Use a different hook** (like `afterSwapReturnDelta`) that allows modifying balances
2. **Defer the swap** - store state and execute later
3. **Use external AMM** - swap against a different pool (like DeepAmmMock)
4. **Modify balances directly** - use `settle()` and `take()` if you have the tokens
