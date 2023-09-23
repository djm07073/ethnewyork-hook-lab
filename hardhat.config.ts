import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";

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
      allowUnlimitedContractSize: true,
      forking: {
        url: "https://l2-uniswap-v4-hook-sandbox-6tl5qq8i4d.t.conduit.xyz",
        blockNumber: 125000,
      },
    },
    uniswap: {
      chainId: 111,
      url: "https://l2-uniswap-v4-hook-sandbox-6tl5qq8i4d.t.conduit.xyz",
    },
  },
};

export default config;
