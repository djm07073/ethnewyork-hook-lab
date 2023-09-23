import { expect } from "chai";
import { CONFIG } from "../config/config";
import { deployHooks } from "../scripts/deployHooks";
import { IPoolManager, MockToken } from "../typechain-types";

import { ethers } from "hardhat";
import { LSBHook } from "../typechain-types/contracts/hooks/LSBHook.sol";

describe("Test PoolManager", () => {
  let poolManager: IPoolManager;
  let LSBhook: LSBHook;
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
    const hookDeployer_f = await ethers.getContractFactory(
      "UniswapHooksFactory"
    );
    const hookDeployer = await hookDeployer_f
      .deploy()
      .then((tx) => tx.waitForDeployment());
    const hookAddress: string = await deployHooks(
      hookDeployer,
      signers[0].address,
      await poolManager.getAddress(),
      "0xA8" //10101000
    ).then((c) => c as string);
    LSBhook = await ethers.getContractAt("LSBHook", hookAddress);
    console.log("ToasterHook deployed");
    token0Address = (await token0.getAddress()).toLocaleLowerCase();
    token1Address = (await token1.getAddress()).toLocaleLowerCase();
    await poolManager
      .initialize(
        {
          currency0:
            token0Address < token1Address ? token0Address : token1Address,
          currency1:
            token0Address < token1Address ? token1Address : token0Address,
          fee: 3000,
          tickSpacing: 60,
          hooks: hookAddress,
        },
        2n ** 96n,
        ethers.encodeBytes32String("1")
      )
      .then((tx) => tx.wait());
    console.log("Create Pool");
  });

  it("Add Liquidity", async () => {
    const signers = await ethers.getSigners();
    expect(await token0.balanceOf(signers[0].address)).to.equal(
      ethers.parseEther("1000000000")
    );
    expect(await token1.balanceOf(signers[0].address)).to.equal(
      ethers.parseEther("1000000000")
    );

    await LSBhook.addLiquidity({
      currency0: token0Address < token1Address ? token0Address : token1Address,
      currency1: token0Address < token1Address ? token1Address : token0Address,
      fee: 3000n,
      tickLower: -10000n,
      tickUpper: 10000n,
      amount0Desired: ethers.parseEther("1000000"),
      amount1Desired: ethers.parseEther("1000000"),
      amount0Min: 1n,
      amount1Min: 1n,
      to: signers[0].address,
      deadline: ethers.MaxUint256,
    });
  });
});
