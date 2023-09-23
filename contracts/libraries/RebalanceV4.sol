// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;
import {TickMath} from "./TickMath.sol";
import {FullMath} from "./FullMath.sol";
import {UnsafeMath} from "./UnsafeMath.sol";
import {SqrtPriceMath} from "./SqrtPriceMath.sol";
import {TickBitmap} from "./TickBitmap.sol";
import {SwapMath} from "./SwapMath.sol";
import {BitMath} from "./BitMath.sol";
import {IPoolManager} from "../interfaces/IPoolManager.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {IDynamicFeeManager} from "../interfaces/IDynamicFeeManager.sol";
import {FeeLibrary} from "../libraries/FeeLibrary.sol";
import {Pool} from "../libraries/Pool.sol";
import {FixedPoint96} from "./FixedPoint96.sol";
import {SafeCast} from "./SafeCast.sol";

/**
 * @title Rebalance V4 Opensource
 * @author Toaster Finance
 * @notice Get Optimal Amount from UniswapV4 PoolManager for Static Fee & Dynamic Fee
 */
library RebalanceV4 {
    using TickMath for int24;
    using FullMath for uint256;
    using UnsafeMath for uint256;
    using PoolIdLibrary for PoolKey;
    using FeeLibrary for uint24;
    using SafeCast for int256;
    using SafeCast for uint256;

    // mapping(address locker => mapping(Currency currency => int256 currencyDelta))
    //     public currencyDelta; // slot0

    // /// @inheritdoc IPoolManager
    // mapping(Currency currency => uint256) public override reservesOf;//slot1

    // mapping(PoolId id => Pool.State) public pools; // slot2

    // struct State {
    //    Slot0 slot0; // first slot
    //    uint256 feeGrowthGlobal0X128; // second slot
    //    uint256 feeGrowthGlobal1X128; // third slot
    //    uint128 liquidity; // fourth slot
    //    mapping(int24 => TickInfo) ticks; // fifth slot
    //    mapping(int16 => uint256) tickBitmap; // sixth slot
    //    mapping(bytes32 => Position.Info) positions; //seventh slot
    //}
    uint256 internal constant MAX_FEE_PIPS = 1e6;
    uint256 internal constant POOLS_SLOT = 2;
    uint256 internal constant TICKS = 4;
    uint256 internal constant BITMAP = 5;

    function getStateSlot(PoolId poolId) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(poolId, POOLS_SLOT));
    }

    // mapping(int16 => PoolId) tickBitmap
    function getTickBitmapSlot(PoolId poolId) private pure returns (bytes32) {
        bytes32 stateSlot = getStateSlot(poolId);
        return bytes32(uint256(stateSlot) + BITMAP);
    }

    // mapping(int24 => TickInfo) ticks;
    function getTicksSlot(PoolId poolId) private pure returns (bytes32) {
        bytes32 stateSlot = getStateSlot(poolId);
        return bytes32(uint256(stateSlot) + TICKS);
    }

    error Invalid_Pool();
    error Invalid_Tick_Range();
    error Math_Overflow();

    struct SwapState {
        uint128 liquidity;
        uint256 sqrtPriceX96;
        int24 tick;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 sqrtRatioLowerX96;
        uint256 sqrtRatioUpperX96;
        uint256 feePips;
        int24 tickSpacing;
    }

    /**
     * @dev Get Optimal Swap in Static Fee Pool
     */
    function getOptimalSwapStaticFee(
        IPoolManager self,
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        uint256 amount0Desired,
        uint256 amount1Desired
    )
        internal
        view
        returns (
            uint256 amountIn,
            uint256 amountOut,
            bool zeroForOne,
            uint160 sqrtPriceX96
        )
    {
        if (amount0Desired == 0 && amount1Desired == 0) return (0, 0, false, 0);
        if (
            tickLower >= tickUpper ||
            tickLower < TickMath.MIN_TICK ||
            tickUpper > TickMath.MAX_TICK
        ) revert Invalid_Tick_Range();

        // intermediate state cache
        SwapState memory state;
        // Populate `SwapState` with hardcoded offsets.

        PoolId id = key.toId();

        (state.sqrtPriceX96, state.tick, , ) = self.getSlot0(id);
        state.liquidity = self.getLiquidity(id);

        state.amount0Desired = amount0Desired;

        state.amount1Desired = amount1Desired;

        state.tickSpacing = key.tickSpacing;

        uint160 sqrtRatioLowerX96 = tickLower.getSqrtRatioAtTick();
        uint160 sqrtRatioUpperX96 = tickUpper.getSqrtRatioAtTick();

        state.sqrtRatioLowerX96 = sqrtRatioLowerX96;

        state.sqrtRatioUpperX96 = sqrtRatioUpperX96;
        state.feePips = key.fee.getStaticFee();

        zeroForOne = isZeroForOne(
            amount0Desired,
            amount1Desired,
            sqrtPriceX96,
            sqrtRatioLowerX96,
            sqrtRatioUpperX96
        );

        // Simulate optimal swap by crossing ticks until the direction reverses.
        crossTicks(self, id, state, sqrtPriceX96, zeroForOne);
        // Active liquidity at the last tick of optimal swap
        uint128 liquidityLast;
        // sqrt(price) at the last tick of optimal swap
        uint160 sqrtPriceLastTickX96;
        // Remaining amount of token0 to add liquidity at the last tick
        uint256 amount0LastTick;
        // Remaining amount of token1 to add liquidity at the last tick
        uint256 amount1LastTick;

        liquidityLast = state.liquidity;

        sqrtPriceLastTickX96 = state.sqrtPriceX96.toUint160();

        amount0LastTick = state.amount0Desired;

        amount1LastTick = state.amount1Desired;

        unchecked {
            if (zeroForOne) {
                // The final price is in range. Use the closed form solution.
                if (sqrtPriceLastTickX96 <= sqrtRatioUpperX96) {
                    sqrtPriceX96 = solveOptimalZeroForOne(state);
                    amountIn =
                        amount0Desired -
                        amount0LastTick +
                        (SqrtPriceMath.getAmount0Delta(
                            sqrtPriceX96,
                            sqrtPriceLastTickX96,
                            liquidityLast,
                            true
                        ) * MAX_FEE_PIPS).div(MAX_FEE_PIPS - state.feePips);
                }
                // The final price is out of range. Simply consume all token0.
                else {
                    amountIn = amount0Desired;
                    sqrtPriceX96 = SqrtPriceMath
                        .getNextSqrtPriceFromAmount0RoundingUp(
                            sqrtPriceLastTickX96,
                            liquidityLast,
                            FullMath.mulDiv(
                                amount0LastTick,
                                MAX_FEE_PIPS - state.feePips,
                                MAX_FEE_PIPS
                            ),
                            true
                        );
                }
                amountOut =
                    amount1LastTick -
                    amount1Desired +
                    SqrtPriceMath.getAmount1Delta(
                        sqrtPriceX96,
                        sqrtPriceLastTickX96,
                        liquidityLast,
                        false
                    );
            } else {
                // The final price is in range. Use the closed form solution.
                if (sqrtPriceLastTickX96 >= sqrtRatioLowerX96) {
                    sqrtPriceX96 = solveOptimalOneForZero(state);
                    amountIn =
                        amount1Desired -
                        amount1LastTick +
                        (SqrtPriceMath.getAmount1Delta(
                            sqrtPriceLastTickX96,
                            sqrtPriceX96,
                            liquidityLast,
                            true
                        ) * MAX_FEE_PIPS).div(MAX_FEE_PIPS - state.feePips);
                }
                // The final price is out of range. Simply consume all token1.
                else {
                    amountIn = amount1Desired;
                    sqrtPriceX96 = SqrtPriceMath
                        .getNextSqrtPriceFromAmount1RoundingDown(
                            sqrtPriceLastTickX96,
                            liquidityLast,
                            FullMath.mulDiv(
                                amount1LastTick,
                                MAX_FEE_PIPS - state.feePips,
                                MAX_FEE_PIPS
                            ),
                            true
                        );
                }
                amountOut =
                    amount0LastTick -
                    amount0Desired +
                    SqrtPriceMath.getAmount0Delta(
                        sqrtPriceLastTickX96,
                        sqrtPriceX96,
                        liquidityLast,
                        false
                    );
            }
        }
    }

    struct CrossTicksCache {
        // the next tick to swap to from the current tick in the swap direction
        int24 tickNext;
        // Ensure the initial `wordPos` doesn't coincide with the starting tick's.
        int16 wordPos;
        bool initialized;
        uint8 bitPos;
    }

    /// @dev Check if the remaining amount is enough to cross the next initialized tick.
    // If so, check whether the swap direction changes for optimal deposit. If so, we swap too much and the final sqrt
    // price must be between the current tick and the next tick. Otherwise the next tick must be crossed.
    function crossTicks(
        IPoolManager self,
        PoolId poolId,
        SwapState memory state,
        uint160 sqrtPriceX96,
        bool zeroForOne
    ) private view {
        CrossTicksCache memory cache;
        cache.wordPos = type(int16).min;
        do {
            unchecked {
                int24 compressed = state.tick / state.tickSpacing;
                if (state.tick < 0 && state.tick % state.tickSpacing != 0)
                    compressed--; // round towards negative infinity

                if (zeroForOne) {
                    (cache.wordPos, cache.bitPos) = position(compressed);
                    // all the 1s at or to the right of the current bitPos
                    uint256 mask = (1 << cache.bitPos) -
                        1 +
                        (1 << cache.bitPos);
                    uint256 masked = uint256(
                        self.extsload(
                            keccak256(
                                abi.encodePacked(
                                    cache.wordPos,
                                    getTickBitmapSlot(poolId)
                                )
                            )
                        )
                    ) & mask; //TODO: fill this slot

                    // if there are no initialized state.ticks to the right of or at the current state.tick, return rightmost in the word
                    cache.initialized = masked != 0;
                    // overflow/underflow is possible, but prevented externally by limiting both state.tickSpacing and state.tick
                    cache.tickNext = cache.initialized
                        ? (compressed -
                            int24(
                                uint24(
                                    cache.bitPos -
                                        BitMath.mostSignificantBit(masked)
                                )
                            )) * state.tickSpacing
                        : (compressed - int24(uint24(cache.bitPos))) *
                            state.tickSpacing;
                } else {
                    // start from the word of the next state.tick, since the current state.tick state doesn't matter
                    (cache.wordPos, cache.bitPos) = position(compressed + 1);
                    // all the 1s at or to the left of the bitPos
                    uint256 mask = ~((1 << cache.bitPos) - 1);
                    uint256 masked = uint256(
                        self.extsload(
                            keccak256(
                                abi.encodePacked(
                                    cache.wordPos,
                                    getTickBitmapSlot(poolId)
                                )
                            )
                        )
                    ) & mask;
                    // if there are no initialized state.ticks to the left of the current state.tick, return leftmost in the word
                    cache.initialized = masked != 0;
                    // overflow/underflow is possible, but prevented externally by limiting both state.tickSpacing and state.tick
                    cache.tickNext = cache.initialized
                        ? (compressed +
                            1 +
                            int24(
                                uint24(
                                    BitMath.leastSignificantBit(masked) -
                                        cache.bitPos
                                )
                            )) * state.tickSpacing
                        : (compressed +
                            1 +
                            int24(uint24(type(uint8).max - cache.bitPos))) *
                            state.tickSpacing;
                }
            }
            if (cache.initialized) continue;
            // sqrt(price) for the next tick (1/0)
            uint160 sqrtPriceNextX96 = cache.tickNext.getSqrtRatioAtTick();
            // The desired amount of token0 to add liquidity after swap
            uint256 amount0Desired;
            // The desired amount of token1 to add liquidity after swap
            uint256 amount1Desired;

            unchecked {
                if (zeroForOne) {
                    // Abuse `amount0Desired` to store `amountIn` to avoid stack too deep errors.
                    (sqrtPriceX96, amount0Desired, amount1Desired) = SwapMath
                        .computeSwapStepExactIn(
                            uint160(state.sqrtPriceX96),
                            sqrtPriceNextX96,
                            state.liquidity,
                            state.amount0Desired,
                            state.feePips
                        );
                    amount0Desired = state.amount0Desired - amount0Desired;
                    amount1Desired = state.amount1Desired + amount1Desired;
                } else {
                    // Abuse `amount1Desired` to store `amountIn` to avoid stack too deep errors.
                    (sqrtPriceX96, amount1Desired, amount0Desired) = SwapMath
                        .computeSwapStepExactIn(
                            uint160(state.sqrtPriceX96),
                            sqrtPriceNextX96,
                            state.liquidity,
                            state.amount1Desired,
                            state.feePips
                        );
                    amount0Desired = state.amount0Desired + amount0Desired;
                    amount1Desired = state.amount1Desired - amount1Desired;
                }
            }

            // If the remaining amount is large enough to consume the current tick and the optimal swap direction
            // doesn't change, continue crossing ticks.
            if (sqrtPriceX96 != sqrtPriceNextX96) break;
            if (
                isZeroForOne(
                    amount0Desired,
                    amount1Desired,
                    sqrtPriceX96,
                    state.sqrtRatioLowerX96,
                    state.sqrtRatioUpperX96
                ) == zeroForOne
            ) {
                int128 liquidityNet = int128(
                    uint128(
                        uint256(
                            self.extsload(
                                keccak256(
                                    abi.encodePacked(
                                        cache.wordPos,
                                        getTicksSlot(poolId)
                                    )
                                )
                            )
                        ) >> 128
                    )
                );

                assembly ("memory-safe") {
                    // If we're moving leftward, we interpret `liquidityNet` as the opposite sign.
                    // If zeroForOne, liquidityNet = -liquidityNet = ~liquidityNet + 1 = -1 ^ liquidityNet + 1.
                    // Therefore, liquidityNet = -zeroForOne ^ liquidityNet + zeroForOne.
                    liquidityNet := add(
                        zeroForOne,
                        xor(sub(0, zeroForOne), liquidityNet)
                    )
                    mstore(state, add(mload(state), liquidityNet))
                }

                state.sqrtPriceX96 = sqrtPriceX96;

                state.tick = zeroForOne ? cache.tickNext - 1 : cache.tickNext;

                state.amount0Desired = amount0Desired;

                state.amount1Desired = amount1Desired;
            } else break;
        } while (true);
    }

    function position(
        int24 tick
    ) private pure returns (int16 wordPos, uint8 bitPos) {
        unchecked {
            wordPos = int16(tick >> 8);
            bitPos = uint8(int8(tick % 256));
        }
    }

    /// @dev Analytic solution for optimal swap between two nearest initialized ticks swapping token0 to token1
    /// @param state Pool state at the last tick of optimal swap
    /// @return sqrtPriceFinalX96 sqrt(price) after optimal swap
    function solveOptimalZeroForOne(
        SwapState memory state
    ) private pure returns (uint160 sqrtPriceFinalX96) {
        /**
         * root = (sqrt(b^2 + 4ac) + b) / 2a
         * `a` is in the order of `amount0Desired`. `b` is in the order of `liquidity`.
         * `c` is in the order of `amount1Desired`.
         * `a`, `b`, `c` are signed integers in two's complement but typed as unsigned to avoid unnecessary casting.
         */
        uint256 a;
        uint256 b;
        uint256 c;
        uint256 sqrtPriceX96;
        unchecked {
            uint256 liquidity;
            uint256 sqrtRatioLowerX96;
            uint256 sqrtRatioUpperX96;
            uint256 feePips;
            uint256 FEE_COMPLEMENT;

            liquidity = state.liquidity;

            sqrtPriceX96 = state.sqrtPriceX96;

            sqrtRatioLowerX96 = state.sqrtRatioLowerX96;

            sqrtRatioUpperX96 = state.sqrtRatioUpperX96;

            feePips = state.feePips;

            FEE_COMPLEMENT = MAX_FEE_PIPS - feePips;

            {
                uint256 a0;
                assembly ("memory-safe") {
                    // amount0Desired = state.amount0Desired
                    let amount0Desired := mload(add(state, 0x60))
                    let liquidityX96 := shl(96, liquidity)
                    // a = amount0Desired + liquidity / ((1 - f) * sqrtPrice) - liquidity / sqrtRatioUpper
                    a0 := add(
                        amount0Desired,
                        div(
                            mul(MAX_FEE_PIPS, liquidityX96),
                            mul(FEE_COMPLEMENT, sqrtPriceX96)
                        )
                    )
                    a := sub(a0, div(liquidityX96, sqrtRatioUpperX96))
                    // `a` is always positive and greater than `amount0Desired`.
                    if lt(a, amount0Desired) {
                        // revert Math_Overflow()
                        mstore(0, 0x20236808)
                        revert(0x1c, 0x04)
                    }
                }
                b = a0.mulDiv96(sqrtRatioLowerX96);
                assembly {
                    b := add(div(mul(feePips, liquidity), FEE_COMPLEMENT), b)
                }
            }
            {
                // c = amount1Desired + liquidity * sqrtPrice - liquidity * sqrtRatioLower / (1 - f)
                uint256 c0 = liquidity.mulDiv96(sqrtPriceX96);
                assembly ("memory-safe") {
                    // c0 = amount1Desired + liquidity * sqrtPrice
                    c0 := add(mload(add(state, 0x80)), c0)
                }
                c =
                    c0 -
                    liquidity.mulDiv96(
                        (MAX_FEE_PIPS * sqrtRatioLowerX96) / FEE_COMPLEMENT
                    );
                b -= c0.mulDiv(FixedPoint96.Q96, sqrtRatioUpperX96);
            }
            assembly {
                a := shl(1, a)
                c := shl(1, c)
            }
        }
        // Given a root exists, the following calculations cannot realistically overflow/underflow.
        unchecked {
            uint256 numerator = FullMath.sqrt(b * b + a * c) + b;
            assembly {
                // `numerator` and `a` must be positive so use `div`.
                sqrtPriceFinalX96 := div(shl(96, numerator), a)
            }
        }
        // The final price must be less than or equal to the price at the last tick.
        // However the calculated price may increase if the ratio is close to optimal.
        assembly {
            // sqrtPriceFinalX96 = min(sqrtPriceFinalX96, sqrtPriceX96)
            sqrtPriceFinalX96 := xor(
                sqrtPriceX96,
                mul(
                    xor(sqrtPriceX96, sqrtPriceFinalX96),
                    lt(sqrtPriceFinalX96, sqrtPriceX96)
                )
            )
        }
    }

    /// @dev Analytic solution for optimal swap between two nearest initialized ticks swapping token1 to token0
    /// @param state Pool state at the last tick of optimal swap
    /// @return sqrtPriceFinalX96 sqrt(price) after optimal swap
    function solveOptimalOneForZero(
        SwapState memory state
    ) private pure returns (uint160 sqrtPriceFinalX96) {
        /**
         * root = (sqrt(b^2 + 4ac) + b) / 2a
         * `a` is in the order of `amount0Desired`. `b` is in the order of `liquidity`.
         * `c` is in the order of `amount1Desired`.
         * `a`, `b`, `c` are signed integers in two's complement but typed as unsigned to avoid unnecessary casting.
         */
        uint256 a;
        uint256 b;
        uint256 c;
        uint256 sqrtPriceX96;
        unchecked {
            uint256 liquidity;
            uint256 sqrtRatioLowerX96;
            uint256 sqrtRatioUpperX96;
            uint256 feePips;
            uint256 FEE_COMPLEMENT;

            liquidity = state.liquidity;

            sqrtPriceX96 = state.sqrtPriceX96;

            sqrtRatioLowerX96 = state.sqrtRatioLowerX96;

            sqrtRatioUpperX96 = state.sqrtRatioUpperX96;

            feePips = state.feePips;

            FEE_COMPLEMENT = MAX_FEE_PIPS - feePips;

            {
                // a = state.amount0Desired + liquidity / sqrtPrice - liquidity / ((1 - f) * sqrtRatioUpper)
                uint256 a0;
                assembly ("memory-safe") {
                    let liquidityX96 := shl(96, liquidity)
                    // a0 = state.amount0Desired + liquidity / sqrtPrice
                    a0 := add(
                        mload(add(state, 0x60)),
                        div(liquidityX96, sqrtPriceX96)
                    )
                    a := sub(
                        a0,
                        div(
                            mul(MAX_FEE_PIPS, liquidityX96),
                            mul(FEE_COMPLEMENT, sqrtRatioUpperX96)
                        )
                    )
                }
                b = a0.mulDiv96(sqrtRatioLowerX96);
                assembly {
                    b := sub(b, div(mul(feePips, liquidity), FEE_COMPLEMENT))
                }
            }
            {
                // c = amount1Desired + liquidity * sqrtPrice / (1 - f) - liquidity * sqrtRatioLower
                uint256 c0 = liquidity.mulDiv96(
                    (MAX_FEE_PIPS * sqrtPriceX96) / FEE_COMPLEMENT
                );
                uint256 amount1Desired;
                assembly ("memory-safe") {
                    // amount1Desired = state.amount1Desired
                    amount1Desired := mload(add(state, 0x80))
                    // c0 = amount1Desired + liquidity * sqrtPrice / (1 - f)
                    c0 := add(amount1Desired, c0)
                }
                c = c0 - liquidity.mulDiv96(sqrtRatioLowerX96);
                assembly ("memory-safe") {
                    // `c` is always positive and greater than `amount1Desired`.
                    if lt(c, amount1Desired) {
                        // revert Math_Overflow()
                        mstore(0, 0x20236808)
                        revert(0x1c, 0x04)
                    }
                }
                b -= c0.mulDiv(FixedPoint96.Q96, state.sqrtRatioUpperX96);
            }
            assembly {
                a := shl(1, a)
                c := shl(1, c)
            }
        }
        // Given a root exists, the following calculations cannot realistically overflow/underflow.
        unchecked {
            uint256 numerator = FullMath.sqrt(b * b + a * c) + b;
            assembly {
                // `numerator` and `a` may be negative so use `sdiv`.
                sqrtPriceFinalX96 := sdiv(shl(96, numerator), a)
            }
        }
        // The final price must be greater than or equal to the price at the last tick.
        // However the calculated price may decrease if the ratio is close to optimal.
        assembly {
            // sqrtPriceFinalX96 = max(sqrtPriceFinalX96, sqrtPriceX96)
            sqrtPriceFinalX96 := xor(
                sqrtPriceX96,
                mul(
                    xor(sqrtPriceX96, sqrtPriceFinalX96),
                    gt(sqrtPriceFinalX96, sqrtPriceX96)
                )
            )
        }
    }

    /// @dev Swap direction to achieve optimal deposit when the current price is in range
    /// @param amount0Desired The desired amount of token0 to be spent
    /// @param amount1Desired The desired amount of token1 to be spent
    /// @param sqrtPriceX96 sqrt(price) at the last tick of optimal swap
    /// @param sqrtRatioLowerX96 The lower sqrt(price) of the position in which to add liquidity
    /// @param sqrtRatioUpperX96 The upper sqrt(price) of the position in which to add liquidity
    /// @return The direction of the swap, true for token0 to token1, false for token1 to token0
    function isZeroForOneInRange(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 sqrtPriceX96,
        uint256 sqrtRatioLowerX96,
        uint256 sqrtRatioUpperX96
    ) private pure returns (bool) {
        unchecked {
            return
                amount0Desired.mulDiv96(sqrtPriceX96).mulDiv96(
                    sqrtPriceX96 - sqrtRatioLowerX96
                ) >
                amount1Desired.mulDiv(
                    sqrtRatioUpperX96 - sqrtPriceX96,
                    sqrtRatioUpperX96
                );
        }
    }

    /// @dev Swap direction to achieve optimal deposit
    /// @param amount0Desired The desired amount of token0 to be spent
    /// @param amount1Desired The desired amount of token1 to be spent
    /// @param sqrtPriceX96 sqrt(price) at the last tick of optimal swap
    /// @param sqrtRatioLowerX96 The lower sqrt(price) of the position in which to add liquidity
    /// @param sqrtRatioUpperX96 The upper sqrt(price) of the position in which to add liquidity
    /// @return The direction of the swap, true for token0 to token1, false for token1 to token0
    function isZeroForOne(
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 sqrtPriceX96,
        uint256 sqrtRatioLowerX96,
        uint256 sqrtRatioUpperX96
    ) internal pure returns (bool) {
        // If the current price is below `sqrtRatioLowerX96`, only token0 is required.
        if (sqrtPriceX96 <= sqrtRatioLowerX96) return false;
        // If the current tick is above `sqrtRatioUpperX96`, only token1 is required.
        else if (sqrtPriceX96 >= sqrtRatioUpperX96) return true;
        else
            return
                isZeroForOneInRange(
                    amount0Desired,
                    amount1Desired,
                    sqrtPriceX96,
                    sqrtRatioLowerX96,
                    sqrtRatioUpperX96
                );
    }
}
