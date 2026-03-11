#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# Deploy MorphoChainlinkOracleV2 — collateral mEDGE / loan USDC.e
# For the market: borrow USDC.e against mEDGE collateral
# ──────────────────────────────────────────────────────────────

RPC="https://evmrpc.0g.ai"
FACTORY="0x5115c1a74abf096150593eecf3e20f016fc9db43"

# Base = collateral = mEDGE
BASE_VAULT="0x0000000000000000000000000000000000000000"
BASE_VAULT_CONVERSION_SAMPLE=1
BASE_FEED1="0xc0a696cb0b56f6eb20ba7629b54356b0df245447"   # mEDGE/USD
BASE_FEED2="0x0000000000000000000000000000000000000000"
BASE_TOKEN_DECIMALS=18                                      # mEDGE

# Quote = loan = USDC.e
QUOTE_VAULT="0x0000000000000000000000000000000000000000"
QUOTE_VAULT_CONVERSION_SAMPLE=1
QUOTE_FEED1="0x6f57Ff507735BcD3d86af83aF77ABD10395b2904"   # USDC/USD Redstone
QUOTE_FEED2="0x0000000000000000000000000000000000000000"
QUOTE_TOKEN_DECIMALS=6                                      # USDC.e

SALT="0x0000000000000000000000000000000000000000000000000000000000000001"

if [ -z "${PRIVATE_KEY:-}" ]; then
  echo "ERROR: PRIVATE_KEY env var is not set."
  echo "  export PRIVATE_KEY=0x..."
  exit 1
fi

echo "==> Verifying mEDGE/USD feed..."
MEDGE_PRICE=$(cast call "$BASE_FEED1" "latestRoundData()(uint80,int256,uint256,uint256,uint80)" --rpc-url "$RPC" | sed -n '2p')
echo "    mEDGE/USD price (raw): $MEDGE_PRICE"

echo "==> Verifying USDC/USD feed..."
USDC_PRICE=$(cast call "$QUOTE_FEED1" "latestRoundData()(uint80,int256,uint256,uint256,uint80)" --rpc-url "$RPC" | sed -n '2p')
echo "    USDC/USD price (raw): $USDC_PRICE"

echo ""
echo "==> Deploying MorphoChainlinkOracleV2 (collateral=mEDGE, loan=USDC.e)..."
echo "    baseFeed1 (mEDGE/USD):  $BASE_FEED1"
echo "    quoteFeed1 (USDC/USD):  $QUOTE_FEED1"
echo "    baseTokenDecimals:      $BASE_TOKEN_DECIMALS"
echo "    quoteTokenDecimals:     $QUOTE_TOKEN_DECIMALS"
echo ""

TX_OUTPUT=$(cast send "$FACTORY" \
  "createMorphoChainlinkOracleV2(address,uint256,address,address,uint256,address,uint256,address,address,uint256,bytes32)" \
  "$BASE_VAULT" "$BASE_VAULT_CONVERSION_SAMPLE" "$BASE_FEED1" "$BASE_FEED2" "$BASE_TOKEN_DECIMALS" \
  "$QUOTE_VAULT" "$QUOTE_VAULT_CONVERSION_SAMPLE" "$QUOTE_FEED1" "$QUOTE_FEED2" "$QUOTE_TOKEN_DECIMALS" \
  "$SALT" \
  --rpc-url "$RPC" \
  --private-key "$PRIVATE_KEY" \
  --legacy \
  --gas-price 5000000000 \
  --json)

TX_HASH=$(echo "$TX_OUTPUT" | jq -r '.transactionHash')
echo "    Tx hash: $TX_HASH"

echo "==> Extracting deployed oracle address from event logs..."
sleep 3

RECEIPT=$(cast receipt "$TX_HASH" --rpc-url "$RPC" --json)
LOG_DATA=$(echo "$RECEIPT" | jq -r '.logs[0].data' 2>/dev/null || echo "")
if [ -n "$LOG_DATA" ] && [ "$LOG_DATA" != "null" ]; then
  ORACLE_ADDRESS="0x$(echo "$LOG_DATA" | cut -c91-130)"
  echo ""
  echo "SUCCESS — Oracle deployed."
  echo "  Oracle address: $ORACLE_ADDRESS"
  echo "  Tx hash:        $TX_HASH"
  echo "  Explorer:       https://chainscan.0g.ai/tx/$TX_HASH"
  echo ""
  echo "Next step — create the market:"
  echo "  ./medge-market.sh $ORACLE_ADDRESS"
else
  echo ""
  echo "WARNING — Could not extract oracle address from logs."
  echo "  Check the tx manually: https://chainscan.0g.ai/tx/$TX_HASH"
fi
