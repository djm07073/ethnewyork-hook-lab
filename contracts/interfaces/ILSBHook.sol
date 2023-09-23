// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;
import {IPoolManager} from "./IPoolManager.sol";
import {CurrencyLibrary, Currency} from "../types/Currency.sol";
import {PoolId, PoolIdLibrary} from "../types/PoolId.sol";
import {PoolKey} from "../types/PoolKey.sol";

interface IToasterHook {
    /******* ERROR *******/
    error PoolNotInitialized();
    error TickSpacingNotDefault();
    error LiquidityDoesntMeetMinimum();
    error SenderMustBeHook();
    error ExpiredPastDeadline();
    error TooMuchSlippage();
    error WrongSwap();
    /******* EVENT *******/
    event AddLiquidity(
        address indexed sender,
        PoolId indexed poolId,
        uint indexed tokenId,
        uint128 amount0,
        uint128 amount1,
        uint128 liquidity
    );
    event RemoveLiquidity(
        PoolId indexed poolId,
        uint indexed tokenId,
        uint128 amount0,
        uint128 amount1,
        uint256 liquidity
    );
    struct CallbackData {
        address sender;
        PoolKey key;
        bool isSwap;
        IPoolManager.ModifyPositionParams modifyParams;
        IPoolManager.SwapParams swapParams;
    }

    struct PoolInfo {
        bool hasAccruedFees;
        address liquidityToken;
    }

    struct AddLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Desired;
        uint256 amount1Desired;
        uint256 amount0Min;
        uint256 amount1Min;
        address to;
        uint256 deadline;
    }

    struct RemoveLiquidityParams {
        Currency currency0;
        Currency currency1;
        uint24 fee;
        uint tokenId;
        uint256 liquidity;
        uint256 deadline;
    }
    struct SwapExactInParams {
        Currency currencyIn;
        Currency currencyOut;
        uint24 fee;
        address from;
        address to;
        uint256 amountIn;
        uint256 amountOutMinimum;
        uint256 deadline;
    }
}
