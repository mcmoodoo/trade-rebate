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
