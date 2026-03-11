# CLAUDE.md

## What This Repo Is

Morpho Blue lending deployment on 0G Mainnet (chain ID 16661), plus a forked Morpho Lite frontend deployed to Vercel.

- **Live site:** https://0g.alphagrowth.markets (also https://alphagrowth.markets)
- **GitHub:** https://github.com/rootdraws/0g-alphagrowth
- **Vercel project:** `morpho-lite-apps` (deployed from `morpho-lite-apps/` monorepo root)

## Chain: 0G Mainnet

- Chain ID: 16661
- RPC: `https://evmrpc.0g.ai`
- Explorer: `https://chainscan.0g.ai`
- Native token: A0GI (18 decimals)
- RPC `eth_getLogs` limit: 1000 blocks per query

## Core Contracts (0G Mainnet)

| Contract | Address |
|---|---|
| Morpho Blue | `0x9CDD13a2212D94C4f12190cA30783B743E83C89e` |
| MetaMorphoV1_1Factory | `0x41528AadC7314658b07Ca6e7213B9b77289B477f` |
| Adaptive Curve IRM | `0xf52e20C42FEc624819D4184226C4777D7cbd767e` |
| Oracle Factory | `0x3A7bB36Ee3f3eE32A60e9a666B5c2E0398307593` |

## Tokens

| Token | Address | Decimals |
|---|---|---|
| USDC.e | `0x1f3aa82227281ca364bfb3d253b0f1af1da6473e` | 6 |
| W0G | `0x1cd0690ff9a693f5ef2dd976660a8dafc81a109c` | 18 |
| mEDGE | `0xa1027783fc183a150126b094037a5eb2f5db30ba` | 18 |

## Markets

### LONG 0G (W0G collateral / USDC.e loan)
- Market ID: `0x22056ed6318ee3403025f5ef17c4ab40e321538fbfa7e3ae9d3db0dde0de9b5d`
- Oracle: `0xa83fb44c3594be82db081f7502ad7d7f3b7134cd`
- LLTV: 86%

### SHORT 0G (USDC.e collateral / W0G loan)
- Market ID: `0x8cf401e68e3ffaf1320f05a77b45d468b6859c50d57a5b4a0799e9cb85612785`
- Oracle: `0xf3123f44b26f8771e53ac95258bfce846258ef13`
- LLTV: 94.5%

### mEDGE/USDC.e (mEDGE collateral / USDC.e loan)
- Market ID: `0x4623ffb46148925715620112cfc92314ba37b47ab0cca42a6337fbf9582ca629`
- Oracle: `0x9a3c7b0458319023604e42fce979918143ac3a9c`
- LLTV: 96.5%

## Oracles

All oracles are `MorphoChainlinkOracleV2` instances deployed via the Oracle Factory.

| Oracle | BASE_FEED1 (collateral/USD) | QUOTE_FEED1 (loan/USD) |
|---|---|---|
| Long 0G | `0xefe76D1C11F267d8735D240f53317F238D8C77c9` (0G/USD Redstone, 8 dec) | `0x6f57Ff507735BcD3d86af83aF77ABD10395b2904` (USDC/USD Redstone, 8 dec) |
| Short 0G | Swapped (USDC is base, 0G is quote) | |
| mEDGE | `0xc0a696cb0b56f6eb20ba7629b54356b0df245447` (mEDGE/USD, 8 dec) | `0x6f57Ff507735BcD3d86af83aF77ABD10395b2904` (USDC/USD Redstone, 8 dec) |

Oracle logic: `price = (baseFeed1Price / quoteFeed1Price) * scaleFactor`. The scaleFactor compensates for token decimal differences (e.g., 18 vs 6 decimals).

## Vaults (MetaMorpho)

| Vault | Address | Asset |
|---|---|---|
| 0g USDC Vault | `0x6003EEe8e9E8b7C72149B16cd88DEA6eeB4681E3` | USDC.e |
| 0g w0g Vault | `0xe29AA6Cd4C2245f7Eb52386E28D82Fc0DE2c32dC` | W0G |

- Vault owner: `0x5304ebB378186b081B99dbb8B6D17d9005eA0448`
- Timelock: 0 (cap changes are instant)
- USDC vault supply queue: [mEDGE market, W0G market] (mEDGE gets new deposits first)
- Both the LONG 0G and mEDGE markets have unlimited caps in the USDC vault

## Frontend (morpho-lite-apps/)

Forked from Morpho's open-source lite-apps monorepo. Modified to support only 0G Mainnet.

### Key modifications from upstream

1. **0G chain definition:** `packages/uikit/src/lib/chains/zerog.ts`
2. **Deployments:** 0G entry in `packages/uikit/src/lib/deployments.ts`
3. **Chain icon:** `packages/uikit/src/assets/chains/zerog.png` + `apps/lite/public/zerog.png`
4. **Only 0G chain:** All other chains removed from `apps/lite/src/lib/wagmi-config.ts`
5. **Default chain:** Set to `zerog` in `apps/lite/src/lib/constants.tsx`
6. **Deployless mode:** 0G added to overrides in `apps/lite/src/lib/overrides.tsx`
7. **Hardcoded vaults/markets:** The 0G RPC is slow and has tight `eth_getLogs` limits, so vault addresses and market IDs are hardcoded directly in:
   - `apps/lite/src/app/dashboard/earn-subpage.tsx` (ZEROG_VAULTS)
   - `apps/lite/src/app/dashboard/borrow-subpage.tsx` (ZEROG_VAULTS + ZEROG_MARKET_IDS)
8. **Curator whitelist:** 0G curator added in `apps/lite/src/lib/curators.ts` (owner address `0x5304ebB378186b081B99dbb8B6D17d9005eA0448`)
9. **Market filter bypass:** 0G markets skip the `totalSupplyAssets > 0` filter so new empty markets still appear

### When adding a new market

1. Add the market ID to `ZEROG_MARKET_IDS` in `borrow-subpage.tsx`
2. If the loan token's vault isn't already in `vaultByLoan` mapping (same file), add it
3. If the market shows 0 liquidity, either deposit into the vault (supply queue routes automatically) or call `reallocate` on the vault
4. Commit, push, and `cd morpho-lite-apps && vercel --prod`

### When adding a new vault

1. Add the vault address to `ZEROG_VAULTS` in both `earn-subpage.tsx` and `borrow-subpage.tsx`
2. Add the vault owner to the curators list in `curators.ts`
3. Add the vault's loan token to the `vaultByLoan` mapping in `borrow-subpage.tsx`

### Vercel deployment

```bash
cd morpho-lite-apps
vercel --prod
```

Config is in `morpho-lite-apps/vercel.json`:
- Install: `pnpm install`
- Build: `pnpm uikit:build && cd apps/lite && pnpm exec vite build`
- Output: `apps/lite/dist`
- Framework: vite
- SPA rewrite: all routes → `/`

## Deploy Scripts

Shell scripts in the repo root for deploying contracts via `cast send`. All require:
- `PRIVATE_KEY` env var exported in the terminal
- `--legacy --gas-price 5000000000` flags (0G doesn't handle EIP-1559 well)

| Script | Purpose |
|---|---|
| `deploy-oracle-long.sh` | Deploy W0G/USDC.e oracle |
| `deploy-oracle-short.sh` | Deploy USDC.e/W0G oracle |
| `deploy-oracle-medge.sh` | Deploy mEDGE/USDC.e oracle |
| `long-market.sh` | Create LONG 0G market |
| `short-market.sh` | Create SHORT 0G market |
| `medge-market.sh` | Create mEDGE/USDC.e market |

## Vault Management

### Setting caps (allow a market to receive vault funds)
```bash
# submitCap (unlimited cap example)
cast send $VAULT "submitCap((address,address,address,address,uint256),uint256)" "($LOAN,$COLLATERAL,$ORACLE,$IRM,$LLTV)" $CAP --rpc-url https://evmrpc.0g.ai --private-key $PRIVATE_KEY --legacy --gas-price 5000000000

# acceptCap (instant if timelock is 0)
cast send $VAULT "acceptCap((address,address,address,address,uint256))" "($LOAN,$COLLATERAL,$ORACLE,$IRM,$LLTV)" --rpc-url https://evmrpc.0g.ai --private-key $PRIVATE_KEY --legacy --gas-price 5000000000
```

### Setting supply queue (controls where new deposits go)
```bash
cast send $VAULT "setSupplyQueue(bytes32[])" "[$MARKET_ID_1,$MARKET_ID_2]" --rpc-url https://evmrpc.0g.ai --private-key $PRIVATE_KEY --legacy --gas-price 5000000000
```

First market in the array gets deposits first.

### Reallocating funds between markets
Use `reallocate` with nested tuple encoding (MarketParams is a sub-struct):
```bash
cast send $VAULT "reallocate(((address,address,address,address,uint256),uint256)[])" "[((loanToken,collateralToken,oracle,irm,lltv),targetAssets),...]" --rpc-url https://evmrpc.0g.ai --private-key $PRIVATE_KEY --legacy --gas-price 5000000000
```

- List withdrawal markets first (set target lower than current supply)
- Then supply markets (set target higher than current supply, usually 0)
- `totalWithdrawn` must be >= `totalSupplied` or it reverts with `InconsistentReallocation`

## IRM

There is one Adaptive Curve IRM (`0xf52e20C42FEc624819D4184226C4777D7cbd767e`) shared across all markets. It adjusts rates per-market based on utilization.

## Common cast queries

```bash
RPC="https://evmrpc.0g.ai"

# Get market params from market ID
cast call 0x9CDD13a2212D94C4f12190cA30783B743E83C89e "idToMarketParams(bytes32)(address,address,address,address,uint256)" $MARKET_ID --rpc-url $RPC

# Get market state (totalSupplyAssets, totalSupplyShares, totalBorrowAssets, totalBorrowShares, lastUpdate, fee)
cast call 0x9CDD13a2212D94C4f12190cA30783B743E83C89e "market(bytes32)(uint128,uint128,uint128,uint128,uint128,uint128)" $MARKET_ID --rpc-url $RPC

# Get vault position in a market (supplyShares, borrowShares, collateral)
cast call 0x9CDD13a2212D94C4f12190cA30783B743E83C89e "position(bytes32,address)(uint256,uint128,uint128)" $MARKET_ID $VAULT --rpc-url $RPC

# Get oracle price
cast call $ORACLE "price()(uint256)" --rpc-url $RPC

# Get price feed answer
cast call $FEED "latestAnswer()(int256)" --rpc-url $RPC
```
