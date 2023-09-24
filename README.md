# ETHNewYork UniswapV4 Hook Project

**I created the three projects below.**

1. LSB-Hook(Liqiudity Snipping Blocking Hook)
2. Rebalancing Library for UniswapV4
3. V4 Quoter

## What Problem I want to solve?

### Issues I wanted to address during ETH New York

- **Liquidity Snipping** : MEV Attack makes LP's motivation loss
- **Predicted UX problem** : The inherent problem with DEX pools that require a ratio of two tokens

- **V4 Quoter** : I created Quoter for V4. This is essential because it's needed later to find routing passes and is needed on the front end.

### Details

- **Liquidity sniping** reduces the amount of fees that go to the liquidity provider, resulting in the liquidity provider earning a significantly lower return than the expected return calculated off-chain. **Preventing liquidity sniping attacks is essential for LPs.**

- When investing in two types of tokens, the ratio of the amount of tokens determined by the price range set by **"you"** must be proportioned by **"you"** through swap. How inconvenient! It was in V3, and it will be in V4.

- In V4, the number of hooks makes it difficult to predict how much you'll receive as a result of a swap, but it's essential whether you're a front-end or optimised router service.

### Liquidity Snipping Attack?

- Liquidity Snipping Attack is a sandwitch attack, an MEV attack, that can cause LPs to receive lower fees than expected. In this attack, the attacker unilaterally receives most of the fees for a large number of swaps in a particular pool in a particular block. Firstly, if there are a lot of swaps, the attacker provides a lot of liquidity in a very small price range where swaps occur. This allows the attacker to take a high percentage of the overall fees. For example, let's say there are a lot of swaps between the price of 10 and 10.1. There is a total of 100 liquidity in this range, but an attacker puts in 900 liquidity and the existing LPs get 1/10th of the fee. He then removes his liquidity at the end of the block. Liquidity providers have a huge disincentive to provide liquidity.

## LSB Hook Working Flow Image

- The lockup time is determined at the same time as the minting, which is determined by a quadratic equation: if an attacker provides a lot of liquidity, they get a fee for it, and if the lockup period is lifted, the existing LPs are expected to suffer equally as much.
- Therefore, I designed the lockup period to be determined by a quadratic equation, so that the attacker has to bear the risk of having his liquidity locked up for a long time while providing liquidity to the pool.
- This makes it very incentivising for MEV attackers to snip liquidity.

  <img width="1376" alt="LSB Hook" src="https://github.com/toaster-finance/UniswapV3-Toaster/assets/89185836/db5bb340-2750-4005-876c-2c340e030457">

## Mathematical formulas in the Rebalancing library

1. **Decide Swap Direction**

   - In uniswap v3 core whitepaper(6.29,6.30) formula
   - If L0 is greater than L1, then token 0 should be swapped and vice versa.
   - Therefore, by comparing the amounts of L0 and L1, we can determine whether to swap token 0 or token 1 to meet the liquidity supply ratio.

2. **Find Liquidity to Swap**
   - Assume that there is a final price (the price at which you max out the liquidity supply). There probably is.
   - L is all liquidity in the range defined by the user.
   - if swap from toke0 to token1,

- $$
   A_0 \rightarrow A_0 - \frac{L}{1-f}\left(\frac{1}{\sqrt{P_{next}}} - \frac{1}{\sqrt{P}}\right)
  $$
- $$
    A_1 \rightarrow A_1 + L\left(\sqrt{P} - \sqrt{P_{next}}\right)
  $$
- Therefore, if the final price exists and we know it, we will know how much to swap in reverse.

3. **Derive the quadratic equation from the equations for the liquidity of token 0 and token 1 then finally get final Price that mean meet the liquidity supply ratio with maximum liquidity**
   $$
      \frac{A_0 - \frac{L}{1-fee}\left(\frac{1}{\sqrt {P_f}} - \frac{1}{\sqrt P}\right)}{\frac{1}{\sqrt{P_f}} - \frac{1}{\sqrt{P_U}}} = \frac{A_1 + L\left(\sqrt{P} - \sqrt{P_f}\right)}{\sqrt{P_f} - \sqrt{P_L}}
   $$
   If we clean up the above equation, we get the coefficients as shown below.

$$
a = A_0 + \frac{L}{(1-fee)\sqrt P} - \frac{L}{\sqrt{P_U}}
$$

$$
b = \sqrt{P_L}A_0 + \frac{L}{1-fee}\sqrt{\frac{P_L}{P}} + \frac{feeL}{1-fee} - L\sqrt{\frac{P}{P_U}} - \frac{U_1}{\sqrt{P_U}} \newline = \sqrt{P_L}a + \frac{feeL}{1-fee}\left(1 - \sqrt\frac{P_L}{P_U}\right) - \frac{c}{\sqrt{P_U}}
$$

$$
c = A_1 + L\sqrt{P} - \frac{L}{1-f}\sqrt{P_L}
$$

Finally, we can plug it into the root formula to get the final price.

$$
\sqrt{P_f} = \frac{b+\sqrt{b^2+4ac}}{2a}
$$

## How can we solve it in code?

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
