import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import dotenv from "dotenv";
import { ethers } from "hardhat";
dotenv.config();
const PK = process.env.PRIVATE_KEY!;
const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.20",
    settings: {
      viaIR: false,
      optimizer: {
        enabled: true,
        runs: 800,
      },
      metadata: {
        // do not include the metadata hash, since this is machine dependent
        // and we want all generated code to be deterministic
        // https://docs.soliditylang.org/en/v0.8.20/metadata.html
        bytecodeHash: "none",
      },
    },
  },
  networks: {
    hardhat: {
      accounts: [
        { privateKey: PK, balance: "1000000000000000000000000000000000" },
      ],
      allowUnlimitedContractSize: true,
      // forking: {
      //   url: "https://1rpc.io/scroll/sepolia",
      //   blockNumber: 994816,
      // },
    },
    uniswap: {
      chainId: 111,
      url: "https://l2-uniswap-v4-hook-sandbox-6tl5qq8i4d.t.conduit.xyz",
    },
    arbitrum_sepolia: {
      chainId: 421614,
      url: "https://sepolia-rollup.arbitrum.io/rpc",
    },
    scroll_sepolia: {
      chainId: 534351,
      url: "https://1rpc.io/scroll/sepolia",
    },
    mantle_test: {
      chainId: 5001,
      url: "https://rpc.testnet.mantle.xyz",
    },
  },
};

export default config;
