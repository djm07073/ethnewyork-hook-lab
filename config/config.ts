type Config = {
  uniswap: {
    poolManager: string;
    salt: string[];
  };
  scroll: {
    poolManager: string;
    salt: string[];
  };
};
export const CONFIG: Config = {
  uniswap: {
    poolManager: "0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9",
    salt: ["274", "636", "715"],
  },
  scroll: {
    poolManager: "0x6B18E29A6c6931af9f8087dbe12e21E495855adA",
    salt: ["274", "636", "715"],
  },
};
