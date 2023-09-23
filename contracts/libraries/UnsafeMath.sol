// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.20;

/// @title Math functions that do not check inputs or outputs
/// @notice Contains methods that perform common math functions but do not do any overflow or underflow checks
library UnsafeMath {
    /// @notice Returns ceil(x / y)
    /// @dev division by 0 has unspecified behavior, and must be checked externally
    /// @param x The dividend
    /// @param y The divisor
    /// @return z The quotient, ceil(x / y)
    function divRoundingUp(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256 z) {
        unchecked {
            assembly {
                z := add(div(x, y), gt(mod(x, y), 0))
            }
        }
    }

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := add(x, y)
        }
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := sub(x, y)
        }
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := mul(x, y)
        }
    }

    function div(uint256 x, uint256 y) internal pure returns (uint256 z) {
        assembly {
            z := div(x, y)
        }
    }

    /// @notice Calculates x * y / 2^96 with full precision.
    function mulDiv96(
        uint256 x,
        uint256 y
    ) internal pure returns (uint256 result) {
        assembly ("memory-safe") {
            // 512-bit multiply `[prod1 prod0] = x * y`.
            // Compute the product mod `2**256` and mod `2**256 - 1`
            // then use the Chinese Remainder Theorem to reconstruct
            // the 512 bit result. The result is stored in two 256
            // variables such that `product = prod1 * 2**256 + prod0`.

            // Least significant 256 bits of the product.
            let prod0 := mul(x, y)
            let mm := mulmod(x, y, not(0))
            // Most significant 256 bits of the product.
            let prod1 := sub(mm, add(prod0, lt(mm, prod0)))

            // Make sure the result is less than `2**256`.
            if iszero(gt(0x1000000000000000000000000, prod1)) {
                // Store the function selector of `FullMulDivFailed()`.
                mstore(0x00, 0xae47f702)
                // Revert with (offset, size).
                revert(0x1c, 0x04)
            }

            // Divide [prod1 prod0] by 2^96.
            result := or(shr(96, prod0), shl(160, prod1))
        }
    }
}
