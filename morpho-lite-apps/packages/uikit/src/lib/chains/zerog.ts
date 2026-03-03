import { defineChain } from "viem";

export const zerog = defineChain({
  id: 16661,
  name: "0G Mainnet",
  network: "zerog",
  nativeCurrency: {
    symbol: "A0GI",
    name: "0G Token",
    decimals: 18,
  },
  rpcUrls: {
    default: {
      http: ["https://evmrpc.0g.ai"],
    },
  },
  blockExplorers: {
    default: {
      name: "0G Explorer",
      url: "https://0g.exploreme.pro",
    },
  },
  contracts: {
    multicall3: {
      address: "0xcA11bde05977b3631167028862bE2a173976CA11",
      blockCreated: 0,
    },
  },
});
