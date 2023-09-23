import { expect } from "chai";
import { deployHooks } from "../scripts/deployHooks";
import {
  IPoolManager,
  MockToken,
  PoolModifyPositionTest,
} from "../typechain-types";

import { ethers } from "hardhat";
import { LSBHook } from "../typechain-types/contracts/hooks/LSBHook.sol";

describe("Test PoolManager", () => {
  let poolManager: IPoolManager;
  let modifyPositionTest: PoolModifyPositionTest;
  let token0: MockToken;
  let token1: MockToken;
  let token0Address: string;
  let token1Address: string;

  before("Deploy PoolManager", async () => {
    const signers = await ethers.getSigners();
    const poolManager_f = await ethers.getContractFactory("PoolManager");
    poolManager = await poolManager_f.deploy(300000);

    const token_f = await ethers.getContractFactory("MockToken");
    token0 = await token_f.deploy("MockToken0", "MT0", 18);
    token1 = await token_f.deploy("MockToken1", "MT1", 18);

    token0Address = await token0.getAddress();
    token1Address = await token1.getAddress();
    modifyPositionTest = await ethers
      .getContractFactory("PoolModifyPositionTest")
      .then(async (c) => c.deploy(await poolManager.getAddress()))
      .then((tx) => tx.waitForDeployment());
  });

  it("Add Liquidity", async () => {
    const signers = await ethers.getSigners();
    expect(await token0.balanceOf(signers[0].address)).to.equal(
      ethers.parseEther("1000000000")
    );
    expect(await token1.balanceOf(signers[0].address)).to.equal(
      ethers.parseEther("1000000000")
    );

    await modifyPositionTest.modifyPosition(
      {
        currency0:
          token0Address < token1Address ? token0Address : token1Address,
        currency1:
          token0Address < token1Address ? token1Address : token0Address,
        fee: 3000n,
        tickSpacing: 60,
        hooks: "0x00660f8B0f9281F547b8563909007507065ED66B",
      },
      {
        tickLower: -10000n,
        tickUpper: 10000n,
        liquidityDelta: ethers.parseEther("1"),
      }
    );
  });
});
