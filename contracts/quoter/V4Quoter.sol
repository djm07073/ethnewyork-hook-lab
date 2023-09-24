// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;
import {IPoolManager} from "../interfaces/IPoolManager.sol";
// import {PoolManager} from "../v4-core/PoolManager.sol";
import {Hooks} from "../libraries/Hooks.sol";
import {BaseHook} from "../v4-periphery/BaseHook.sol";
import {SafeCast} from "../libraries/SafeCast.sol";
import {IHooks} from "../interfaces/IHooks.sol";
import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {TickMath} from "../libraries/TickMath.sol";
import {BalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {IERC20Minimal} from "../interfaces/external/IERC20Minimal.sol";
import {ILockCallback} from "../interfaces/callback/ILockCallback.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";
import {FullMath} from "../libraries/FullMath.sol";
import {FixedPoint96} from "../libraries/FixedPoint96.sol";
import {LiquidityAmounts} from "../libraries/LiquidityAmounts.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {RebalanceV4} from "../libraries/RebalanceV4.sol";

contract V4Quoter {
    IPoolManager public poolManager;

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }

    struct OptimalSwapStaticParams {
        /// @notice The lower currency of the pool, sorted numerically
        Currency currency0;
        /// @notice The higher currency of the pool, sorted numerically
        Currency currency1;
        /// @notice The pool swap fee, capped at 1_000_000. The upper 4 bits determine if the hook sets any fees.
        uint24 fee;
        /// @notice Ticks that involve positions must be a multiple of tick spacing
        int24 tickSpacing;
        /// @notice The hooks of the pool
        IHooks hooks;
        int24 tickLower;
        int24 tickUpper;
        uint amount0Desired;
        uint amount1Desired;
    }

    function getOptimalSwapAmountStaticFee(
        OptimalSwapStaticParams memory params
    ) external view {
        PoolKey memory key = PoolKey({
            currency0: params.currency0 < params.currency1
                ? params.currency0
                : params.currency1,
            currency1: params.currency1 < params.currency0
                ? params.currency0
                : params.currency1,
            fee: params.fee,
            tickSpacing: params.tickSpacing,
            hooks: params.hooks
        });
        RebalanceV4.getOptimalSwapStaticFee(
            poolManager,
            key,
            params.tickLower,
            params.tickUpper,
            params.amount0Desired,
            params.amount1Desired
        );
    }

    struct ExactInputParams {
        /// @notice The lower currency of the pool, sorted numerically
        Currency currency0;
        /// @notice The higher currency of the pool, sorted numerically
        Currency currency1;
        /// @notice The pool swap fee, capped at 1_000_000. The upper 4 bits determine if the hook sets any fees.
        uint24 fee;
        /// @notice Ticks that involve positions must be a multiple of tick spacing
        int24 tickSpacing;
        /// @notice The hooks of the pool
        IHooks hooks;
        int24 tickLower;
        int24 tickUpper;
        uint amount0Desired;
        uint amount1Desired;
    }

    function quoteExactSingle(
        PoolKey memory key,
        IPoolManager.SwapParams memory params,
        bytes calldata hookData
    ) public returns (uint256 amountOut) {
        try poolManager.swap(key, params, hookData) {} catch (
            bytes memory reason
        ) {
            return parseRevertReason(reason);
        }
    }

    function parseRevertReason(
        bytes memory reason
    ) private pure returns (uint256) {
        if (reason.length != 32) {
            if (reason.length < 68) revert("Unexpected error");
            assembly {
                reason := add(reason, 0x04)
            }
            revert(abi.decode(reason, (string)));
        }
        return abi.decode(reason, (uint256));
    }
}
