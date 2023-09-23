// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {IPoolManager} from "../interfaces/IPoolManager.sol";
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
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {ILSBHook} from "../interfaces/ILSBHook.sol";
import {LSBERC1155} from "../token/LSBERC1155.sol";
import {LiquidityAmounts} from "../libraries/LiquidityAmounts.sol";
import "hardhat/console.sol";

/**
 * @title LSBHook
 * @author Toaster Finance
 * @notice Toaster Finance for Rebalancing & Block Liquidity Snipping
 */
contract LSBHook is BaseHook, ILockCallback, ILSBHook {
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;
    using PoolIdLibrary for PoolKey;
    using SafeCast for uint256;
    using SafeCast for uint128;
    string public uri;
    address public owner;
    bytes internal constant ZERO_BYTES = bytes("");
    /// @dev Min tick for full range with tick spacing of 60
    int24 internal constant MIN_TICK = -887220;
    /// @dev Max tick for full range with tick spacing of 60
    int24 internal constant MAX_TICK = -MIN_TICK;
    int256 internal constant MAX_INT = type(int256).max;
    uint16 internal constant MINIMUM_LIQUIDITY = 1000;

    mapping(PoolId => PoolInfo) public poolInfo;

    modifier ensure(uint256 deadline) {
        if (deadline < block.timestamp) revert ExpiredPastDeadline();
        _;
    }
    modifier onlyOwner() {
        if (msg.sender != owner) revert NotOwner();
        _;
    }

    constructor(
        address _owner,
        IPoolManager _poolManager
    ) BaseHook(_poolManager) {
        owner = _owner;
    }

    function getHooksCalls() public pure override returns (Hooks.Calls memory) {
        return
            Hooks.Calls({
                beforeInitialize: true,
                afterInitialize: false,
                beforeModifyPosition: true,
                afterModifyPosition: false,
                beforeSwap: true,
                afterSwap: false,
                beforeDonate: false,
                afterDonate: false
            });
    }

    /***** Hook Function  *****/
    function beforeInitialize(
        address,
        PoolKey calldata key,
        uint160,
        bytes calldata hookData
    ) external override returns (bytes4) {
        if (key.tickSpacing != int24(key.fee / 50))
            revert TickSpacingNotDefault();

        PoolId poolId = key.toId();

        uint256 basicInterval = abi.decode(hookData, (uint256));

        address poolToken = address(
            new LSBERC1155(uri, basicInterval, key.tickSpacing, poolId)
        );

        poolInfo[poolId] = PoolInfo({
            hasAccruedFees: false,
            liquidityToken: poolToken
        });

        return BaseHook.beforeInitialize.selector;
    }

    function beforeModifyPosition(
        address sender,
        PoolKey calldata,
        IPoolManager.ModifyPositionParams calldata,
        bytes calldata
    ) external view override returns (bytes4) {
        if (sender != address(this)) revert SenderMustBeHook();

        return BaseHook.beforeModifyPosition.selector;
    }

    function beforeSwap(
        address,
        PoolKey calldata key,
        IPoolManager.SwapParams calldata,
        bytes calldata
    ) external override returns (bytes4) {
        PoolId poolId = key.toId();

        if (!poolInfo[poolId].hasAccruedFees) {
            PoolInfo storage pool = poolInfo[poolId];
            pool.hasAccruedFees = true;
        }

        return BaseHook.beforeSwap.selector;
    }

    /******* Invest Function *******/
    function addLiquidity(
        AddLiquidityParams calldata params
    ) external ensure(params.deadline) returns (uint128 liquidity) {
        PoolKey memory key = PoolKey({
            currency0: params.currency0,
            currency1: params.currency1,
            fee: params.fee,
            tickSpacing: int24(params.fee / 50),
            hooks: IHooks(address(this))
        });

        PoolId poolId = key.toId();

        (uint160 sqrtPriceX96, , , ) = poolManager.getSlot0(poolId);

        if (sqrtPriceX96 == 0) revert PoolNotInitialized();

        PoolInfo storage pool = poolInfo[poolId];

        uint128 poolLiquidity = poolManager.getLiquidity(
            poolId,
            address(this),
            params.tickLower,
            params.tickUpper
        );

        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(params.tickLower),
            TickMath.getSqrtRatioAtTick(params.tickUpper),
            params.amount0Desired,
            params.amount1Desired
        );

        if (poolLiquidity == 0 && liquidity <= MINIMUM_LIQUIDITY) {
            revert LiquidityDoesntMeetMinimum();
        }
        BalanceDelta addedDelta = _modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: params.tickLower,
                tickUpper: params.tickUpper,
                liquidityDelta: liquidity.toInt256()
            })
        );

        LSBERC1155(pool.liquidityToken).mint(
            params.to,
            params.tickLower,
            params.tickUpper,
            liquidity
        );
        uint128 amount0 = uint128(addedDelta.amount0());
        uint128 amount1 = uint128(addedDelta.amount1());
        if (amount0 < params.amount0Min || amount1 < params.amount1Min) {
            revert TooMuchSlippage();
        }

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    function removeLiquidity(
        RemoveLiquidityParams calldata params
    ) public virtual ensure(params.deadline) returns (BalanceDelta delta) {
        PoolKey memory key = PoolKey({
            currency0: params.currency0,
            currency1: params.currency1,
            fee: params.fee,
            tickSpacing: int24(params.fee / 50),
            hooks: IHooks(address(this))
        });

        PoolId poolId = key.toId();

        PoolInfo storage pool = poolInfo[poolId];
        LSBERC1155 toast = LSBERC1155(pool.liquidityToken);
        (, int24 tickLower, int24 tickUpper) = toast.positions(params.tokenId);
        if (pool.liquidityToken == address(0)) revert PoolNotInitialized();

        delta = _modifyPosition(
            key,
            IPoolManager.ModifyPositionParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: -(params.liquidity.toInt256())
            })
        );
        uint128 amount0 = uint128(delta.amount0());
        uint128 amount1 = uint128(delta.amount1());

        toast.burn(msg.sender, params.tokenId, params.liquidity);
        emit RemoveLiquidity(
            poolId,
            params.tokenId,
            amount0,
            amount1,
            params.liquidity
        );

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    /**** Swap ****/
    function swapExactIn(
        SwapExactInParams calldata params
    ) public virtual ensure(params.deadline) returns (BalanceDelta delta) {
        address from;
        bool isZeroForOne = params.currencyIn < params.currencyOut;
        // only call when do Rebalancing
        if (msg.sender == address(this)) {
            from = params.from;
        } else {
            from = msg.sender;
        }
        PoolKey memory key;
        if (isZeroForOne) {
            key = PoolKey({
                currency0: params.currencyOut,
                currency1: params.currencyIn,
                fee: params.fee,
                tickSpacing: int24(params.fee / 50),
                hooks: IHooks(address(this))
            });
        } else {
            key = PoolKey({
                currency0: params.currencyIn,
                currency1: params.currencyOut,
                fee: params.fee,
                tickSpacing: int24(params.fee / 50),
                hooks: IHooks(address(this))
            });
        }

        delta = _swap(
            key,
            IPoolManager.SwapParams({
                zeroForOne: isZeroForOne,
                amountSpecified: params.amountIn.toInt256(),
                sqrtPriceLimitX96: type(uint160).max
            })
        );
        uint amountOut = isZeroForOne
            ? uint(uint128(-delta.amount1()))
            : uint(uint128(-delta.amount0()));
        if (amountOut < params.amountOutMinimum) revert TooMuchSlippage();

        uint256 ethBalance = address(this).balance;
        if (ethBalance > 0) {
            CurrencyLibrary.NATIVE.transfer(msg.sender, ethBalance);
        }
    }

    /**** Internal Function ****/
    function _modifyPosition(
        PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params
    ) internal returns (BalanceDelta delta) {
        //IPoolManager.SwapParams will not effect after all of operation
        delta = abi.decode(
            poolManager.lock(
                abi.encode(
                    CallbackData(
                        msg.sender,
                        key,
                        false,
                        params,
                        IPoolManager.SwapParams({
                            zeroForOne: false,
                            amountSpecified: 0,
                            sqrtPriceLimitX96: type(uint160).max
                        })
                    )
                )
            ),
            (BalanceDelta)
        );
    }

    function _swap(
        PoolKey memory key,
        IPoolManager.SwapParams memory params
    ) internal returns (BalanceDelta delta) {
        delta = abi.decode(
            poolManager.lock(
                abi.encode(
                    CallbackData(
                        msg.sender,
                        key,
                        true,
                        IPoolManager.ModifyPositionParams({
                            tickLower: MIN_TICK,
                            tickUpper: MAX_TICK,
                            liquidityDelta: type(int).min
                        }),
                        params
                    )
                )
            ),
            (BalanceDelta)
        );
    }

    function _settleDeltas(
        address sender,
        PoolKey memory key,
        BalanceDelta delta
    ) internal {
        _settleDelta(sender, key.currency0, uint128(delta.amount0()));
        _settleDelta(sender, key.currency1, uint128(delta.amount1()));
    }

    // sender -> pool
    function _settleDelta(
        address sender,
        Currency currency,
        uint128 amount
    ) internal {
        if (currency.isNative()) {
            poolManager.settle{value: amount}(currency);
        } else {
            if (sender == address(this)) {
                currency.transfer(address(poolManager), amount);
            } else {
                IERC20Minimal(Currency.unwrap(currency)).transferFrom(
                    sender,
                    address(poolManager),
                    amount
                );
            }
            poolManager.settle(currency);
        }
    }

    // pool -> sender
    function _takeDeltas(
        address sender,
        PoolKey memory key,
        BalanceDelta delta
    ) internal {
        poolManager.take(
            key.currency0,
            sender,
            uint256(uint128(-delta.amount0()))
        );
        poolManager.take(
            key.currency1,
            sender,
            uint256(uint128(-delta.amount1()))
        );
    }

    function _swapDeltas(
        address sender,
        PoolKey memory key,
        BalanceDelta delta
    ) internal {
        int128 amount0Delta = delta.amount0();
        int128 amount1Delta = delta.amount1();

        if (amount0Delta > 0 && amount1Delta < 0) {
            _settleDelta(sender, key.currency0, uint128(amount0Delta));
            poolManager.take(
                key.currency1,
                sender,
                uint256(uint128(-amount1Delta))
            );
        } else if (amount0Delta < 0 && amount1Delta > 0) {
            _settleDelta(sender, key.currency1, uint128(amount1Delta));
            poolManager.take(
                key.currency0,
                sender,
                uint256(uint128(-amount0Delta))
            );
        } else {
            revert WrongSwap();
        }
    }

    function _removeLiquidity(
        PoolKey memory key,
        IPoolManager.ModifyPositionParams memory params,
        int24 tickLower,
        int24 tickUpper
    ) internal returns (BalanceDelta delta) {
        PoolId poolId = key.toId();
        PoolInfo storage pool = poolInfo[poolId];

        uint256 liquidityToRemove = FullMath.mulDiv(
            uint256(-params.liquidityDelta),
            poolManager.getLiquidity(
                poolId,
                address(this),
                tickLower,
                tickUpper
            ),
            LSBERC1155(pool.liquidityToken).getSupply(tickLower, tickUpper)
        );

        params.liquidityDelta = -(liquidityToRemove.toInt256());
        delta = poolManager.modifyPosition(key, params, ZERO_BYTES);
        pool.hasAccruedFees = false;
    }

    /***** Key Function ******/
    function lockAcquired(
        bytes calldata rawData
    )
        external
        override(ILockCallback, BaseHook)
        poolManagerOnly
        returns (bytes memory)
    {
        CallbackData memory data = abi.decode(rawData, (CallbackData));
        BalanceDelta delta;
        if (!data.isSwap) {
            if (data.modifyParams.liquidityDelta < 0) {
                delta = _removeLiquidity(
                    data.key,
                    data.modifyParams,
                    data.modifyParams.tickLower,
                    data.modifyParams.tickUpper
                );
                _takeDeltas(data.sender, data.key, delta);
            } else {
                delta = poolManager.modifyPosition(
                    data.key,
                    data.modifyParams,
                    ZERO_BYTES
                );
                _settleDeltas(data.sender, data.key, delta);
            }
        } else {
            delta = poolManager.swap(data.key, data.swapParams, ZERO_BYTES);
        }
        return abi.encode(delta);
    }

    /**** Config Function ****/

    function setUri(string memory _uri) external onlyOwner {
        uri = _uri;
    }
}
