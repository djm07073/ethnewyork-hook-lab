# ETHNewYork-LSB-Hook(Liqiudity Snipping Blocking Hook)

## What Problem we want to solve?

### Key word

- **Liquidity Snipping** : MEV Attack makes LP's motivation loss

### Details

- Liquidity sniping reduces the amount of fees that go to the liquidity provider, resulting in the liquidity provider earning a significantly lower return than the expected return calculated off-chain. Preventing liquidity sniping attacks is essential for LPs.

## How can we solve it?

- We use LP ERC1155 tokens as proof of liquidity. However, this LP Token is minted with an id determined by keccack256 (blockTime, tickLower, tickUpper). And the lockup period is determined at the same time as minting, so that users who have already invested do not feel deprived.

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

        if (position.blockTime + lock[account] > block.timestamp) {
            revert PreventLiquiditySnipping();
        }
    }

```

- We can use
