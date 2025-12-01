## Trade Rebate - arbitraging my own trade

You spill money on the floor during the swap →
Your hook picks the money back up →
But it’s still your money either way.

## Proof of Concept

Write a minimal PoC Uniswap v4 hook in modern Solidity that restores the pool price back to its pre-swap value using a post-swap hook. No external price feeds. Snapshot the price before the swap, perform the swap, then in the post-swap hook execute a balancing swap to return the pool to the original sqrtPriceX96. Include:

A clean, compilable Hook contract

How it stores the pre-swap price

How it triggers the corrective swap

Example test using Foundry
Keep code concise.

## So Far

I've got USDC on the local anvil fork. I am able to swap default anvil's account's ETH for USDC: 5ETH -> USDC

I can then provide that token pair as liquidity to my own Pool with a hook attached.

What can I do? Take out a flash loan from AAVE/Morpho...

### Flash‑loan arbitrage rebate (experimental)

- **What it does**: The `TradeRebate` hook snapshots the pre‑swap tick in `beforeSwap` and, if enabled, uses `afterSwap` to take an Aave v3 flash loan, trade against a deep‑liquidity AMM (mocked), repay, and record any USDC profit on its internal ledger (`surplusByToken`).
- **Deploy/run**:
  - `just deploy-hook` then `just create-pool` (deploys `TradeRebate` and `DeepAmmMock`).
- **Enable per swap**:
  - Pass `hookData = abi.encode(trader, true)` via your router so `afterSwap` attempts the in‑tx arb.
- **Notes**:
  - Mock AMM must be pre‑funded with WETH/USDC to pay out; wired addresses on Arbitrum fork: Aave Pool `0x794a61358D6845594F94dc1DB02A252b5b4814aD`, WETH `0x82aF...`, USDC `0xFF97...`.
  - Experimental; if profit ≤ premium/slippage, callback can revert. Test on forks only.
