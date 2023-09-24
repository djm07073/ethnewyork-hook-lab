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

### Liquidity Snipping Attack?

- Liquidity Snipping Attack is a sandwitch attack, an MEV attack, that can cause LPs to receive lower fees than expected. In this attack, the attacker unilaterally receives most of the fees for a large number of swaps in a particular pool in a particular block. Firstly, if there are a lot of swaps, the attacker provides a lot of liquidity in a very small price range where swaps occur. This allows the attacker to take a high percentage of the overall fees. For example, let's say there are a lot of swaps between the price of 10 and 10.1. There is a total of 100 liquidity in this range, but an attacker puts in 900 liquidity and the existing LPs get 1/10th of the fee. He then removes his liquidity at the end of the block. Liquidity providers have a huge disincentive to provide liquidity.

## How can we solve it?

- I needed to look up information about the pool to redistribute the amount of tokens and wrote the following code to get information about the ticks

```
    function getStateSlot(PoolId poolId) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(poolId, POOLS_SLOT));
    }
    function getTickBitmapSlot(PoolId poolId) private pure returns (bytes32) {
        bytes32 stateSlot = getStateSlot(poolId);
        return bytes32(uint256(stateSlot) + BITMAP);
    }
    function getTicksSlot(PoolId poolId) private pure returns (bytes32) {
        bytes32 stateSlot = getStateSlot(poolId);
        return bytes32(uint256(stateSlot) + TICKS);
    }
```

- (Digression) I'm trying to create ticklens after ETH New York

- I then created a function that could take the information about the tick from above and use it to simulate a crossTick. With this, I created the Rebalance library to help redistribute the amount of tokens.

```
function crossTicks(
        IPoolManager self,
        PoolId poolId,
        SwapState memory state,
        uint160 sqrtPriceX96,
        bool zeroForOne
    ) private view
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

- The lockup time is determined at the same time as the minting, which is determined by a quadratic equation: if an attacker provides a lot of liquidity, they get a fee for it, and if the lockup period is lifted, the existing LPs are expected to suffer equally as much. Therefore, I designed the lockup period to be determined by a quadratic equation, so that the attacker has to bear the risk of having his liquidity locked up for a long time while providing liquidity to the pool. This makes it very incentivising for MEV attackers to snip liquidity.

```
function mint(
        address account,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount
    ) external {
        Position memory position = Position(
            block.timestamp,
            tickLower,
            tickUpper
        );
        uint id = uint(keccak256(abi.encode(position)));
        positions[id] = position;
        updateSupply(amount, tickLower, tickUpper, true);
        tokenIdList[account].push(id);
        lockUp[account] = (basicInterval * (amount / 1e19)) ** 2;
        _mint(account, id, amount, "");
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

## Working Flow Image

<img width="1376" alt="LSB Hook" src="https://github.com/toaster-finance/UniswapV3-Toaster/assets/89185836/db5bb340-2750-4005-876c-2c340e030457">
