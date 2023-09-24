// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {PoolId} from "../types/PoolId.sol";

/**
 * @title LSB Finance Hook's ERC1155
 * @author LSB Finance
 * @notice ERC1155 designed by role of blocking liquidity snipping
 */
contract LSBERC1155 is ERC1155, Ownable {
    struct Position {
        uint blockTime;
        int24 tickLower;
        int24 tickUpper;
    }

    uint256 public immutable basicInterval;
    int24 public immutable tickSpacing;
    PoolId public immutable poolid;
    mapping(address => uint) public lockUp;
    mapping(address => uint[]) tokenIdList;
    mapping(int24 => uint) supplyInfo;
    mapping(uint => Position) public positions;
    error PreventLiquiditySnipping();

    constructor(
        string memory uri_,
        uint256 _interval,
        int24 _tickSpacing,
        PoolId _poolid
    ) ERC1155(uri_) Ownable() {
        basicInterval = _interval;
        tickSpacing = _tickSpacing;
        poolid = _poolid;
    }

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

    function burn(address account, uint256 id, uint256 amount) external {
        blockLiquiditySnipping(account, id);
        Position memory position = positions[id];
        updateSupply(amount, position.tickLower, position.tickUpper, false);
        _burn(account, id, amount);
    }

    function _burn(address from, uint256 id, uint256 amount) internal override {
        if (balanceOf(from, id) == amount) {
            for (uint i = 0; i < tokenIdList[from].length; i++) {
                if (tokenIdList[from][i] == id) {
                    delete tokenIdList[from][i];
                    break;
                }
            }
        }
        super._burn(from, id, amount);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 id,
        uint256 amount,
        bytes memory data
    ) public virtual override {
        blockLiquiditySnipping(from, id);

        for (uint i = 0; i < tokenIdList[from].length; i++) {
            if (tokenIdList[from][i] == id) {
                delete tokenIdList[from][i];
                tokenIdList[to].push(id);
                break;
            }
        }

        super.safeTransferFrom(from, to, id, amount, data);
    }

    function blockLiquiditySnipping(address account, uint id) internal view {
        Position memory position = positions[id];
        if (position.blockTime + lockUp[account] > block.timestamp) {
            revert PreventLiquiditySnipping();
        }
    }

    function updateSupply(
        uint amount,
        int24 tickLower,
        int24 tickUpper,
        bool isAdd
    ) internal {
        uint supplyPerTick;
        unchecked {
            supplyPerTick =
                (amount * uint(int256(tickSpacing + 1))) /
                uint(int(tickUpper - tickLower));
        }
        for (int24 t = tickLower; t <= tickUpper; t = t + tickSpacing) {
            if (isAdd) {
                supplyInfo[t] += supplyPerTick;
            } else {
                supplyInfo[t] -= supplyPerTick;
            }
        }
    }

    function getSupply(
        int24 tickLower,
        int24 tickUpper
    ) external view returns (uint supply) {
        for (int24 t = tickLower; t <= tickUpper; t = t + tickSpacing) {
            supply += supplyInfo[t];
        }
    }
}
