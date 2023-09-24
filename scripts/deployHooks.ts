import { expect } from "chai";
import { ethers } from "hardhat";
import { CONFIG } from "../config/config";
import { UniswapHooksFactory } from "../typechain-types";

export const deployHooks = async (
  hookDeployer: UniswapHooksFactory,
  owner: string,
  poolManager: string,
  prefix: string
) => {
  let expectedAddress = "";

  for (let salt = 0; salt < 1000; salt++) {
    expectedAddress = await hookDeployer.getPrecomputedHookAddress(
      owner,
      poolManager,
      ethers.encodeBytes32String(salt.toString())
    );

    if (_doesAddressStartWith(BigInt(expectedAddress), BigInt(prefix))) {
      await hookDeployer
        .deploy(owner, poolManager, ethers.encodeBytes32String(salt.toString()))
        .then((tx) => tx.wait());

      console.log("Salt:", salt);
      console.log("Address:", expectedAddress);

      break;
    }
  }

  return expectedAddress;
};

function _doesAddressStartWith(_address: bigint, _prefix: bigint) {
  return _address / 2n ** (8n * 19n) == _prefix;
}
async function main() {
  const singers = await ethers.getSigners();
  const hookDeployer_f = await ethers.getContractFactory("UniswapHooksFactory");
  const hookDeployer = await hookDeployer_f
    .deploy()
    .then((tx) => tx.waitForDeployment());
  await deployHooks(
    hookDeployer,
    singers[0].address,
    CONFIG.uniswap.poolManager,
    "0xA8" // 1001
  );
}
main();
