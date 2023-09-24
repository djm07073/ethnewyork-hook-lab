# ETHNewYork-LSB-Hook(Liqiudity Snipping Blocking Hook)

## What Problem we want to solve?

### Key word

- **Predicted UX problem** : The inherent problem with DEX pools that require a ratio of two tokens
- **Liquidity Snipping** : MEV Attack makes LP's motivation loss
- **V4 Quoter** : I created Quoter for V4. This is essential because it's needed later to find routing passes and is needed on the front end.

### Details

- When investing in two types of tokens, the ratio of the amount of tokens determined by the price range set by **"you"** must be proportioned by **"you"** through swap. How inconvenient! It was in V3, and it will be in V4.

- Liquidity sniping reduces the amount of fees that go to the liquidity provider, resulting in the liquidity provider earning a significantly lower return than the expected return calculated off-chain. Preventing liquidity sniping attacks is essential for LPs.

- In V4, the number of hooks makes it difficult to predict how much you'll receive as a result of a swap, but it's essential whether you're a front-end or optimised router service.

## How can we solve it?

- I needed to look up information about the pool to redistribute the amount of tokens and wrote the following code to get information about the ticks

```

```

- I use LP ERC1155 tokens as proof of liquidity. However, this LP Token is minted with an id determined by keccack256 (blockTime, tickLower, tickUpper). And the lockup period is determined at the same time as minting, so that users who have already invested do not feel deprived.

```
    struct Position {
        uint blockTime;
        int24 tickLower;
        int24 tickUpper;
    }
```

```
    mapping(uint => Position) public positions;
```

```
    function blockLiquiditySnipping(address account, uint id) internal view {
        Position memory position = positions[id];
        if (position.blockTime + lockUp[account] > block.timestamp) {
            revert PreventLiquiditySnipping();
        }
    }

```

- You can do this by virtually running the simulation in a try - catch fashion, as we did in V3. However, since this is V4, the parameters are slightly different.

```

function quoteExactSingle(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        bytes calldata hookData
    ) external returns (uint256 amountOut) {
        try poolManager.swap(key, params, hookData) {} catch (
            bytes memory reason
        ) {
            return parseRevertReason(reason);
        }
    }

```
