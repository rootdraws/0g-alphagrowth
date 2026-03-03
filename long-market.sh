#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# Create Morpho Blue Market — borrow USDC.e / collateral w0G
# LLTV: 86%
# ──────────────────────────────────────────────────────────────
# Usage:
#   export PRIVATE_KEY=0x...
#   ./long-market.sh <ORACLE_ADDRESS>
# ──────────────────────────────────────────────────────────────

RPC="https://evmrpc.0g.ai"
MORPHO="0x9CDD13a2212D94C4f12190cA30783B743E83C89e"

LOAN_TOKEN="0x1f3aa82227281ca364bfb3d253b0f1af1da6473e"       # USDC.e (6 decimals)
COLLATERAL_TOKEN="0x1cd0690ff9a693f5ef2dd976660a8dafc81a109c"  # w0G (18 decimals)
IRM="0xf52e20c42fec624819d4184226c4777d7cbd767e" #IRM
LLTV="860000000000000000"

# ── Parse oracle address argument ────────────────────────────

if [ -z "${1:-}" ]; then
  echo "ERROR: Oracle address required."
  echo "  Usage: ./long-market.sh <ORACLE_ADDRESS>"
  echo ""
  echo "  Deploy the oracle first: ./deploy-oracle-long.sh"
  exit 1
fi

ORACLE="$1"

# ── Sanity checks ────────────────────────────────────────────

if [ -z "${PRIVATE_KEY:-}" ]; then
  echo "ERROR: PRIVATE_KEY env var is not set."
  echo "  export PRIVATE_KEY=0x..."
  exit 1
fi

if ! command -v cast &> /dev/null; then
  echo "ERROR: 'cast' not found. Install Foundry: https://getfoundry.sh"
  exit 1
fi

# ── Step 1: Verify oracle responds ──────────────────────────

echo "==> Verifying oracle at $ORACLE..."
ORACLE_PRICE=$(cast call "$ORACLE" "price()(uint256)" --rpc-url "$RPC" 2>&1) || {
  echo "ABORT: Oracle at $ORACLE does not respond to price(). Is this the right address?"
  exit 1
}
echo "    Oracle price (raw): $ORACLE_PRICE"

# ── Step 2: Pre-flight — LLTV enabled? ──────────────────────

echo "==> Checking isLltvEnabled($LLTV)..."
LLTV_OK=$(cast call "$MORPHO" "isLltvEnabled(uint256)(bool)" "$LLTV" --rpc-url "$RPC")
echo "    Result: $LLTV_OK"

if [ "$LLTV_OK" != "true" ]; then
  echo "ABORT: LLTV $LLTV is not enabled on Morpho."
  exit 1
fi

# ── Step 3: Pre-flight — IRM enabled? ───────────────────────

echo "==> Checking isIrmEnabled($IRM)..."
IRM_OK=$(cast call "$MORPHO" "isIrmEnabled(address)(bool)" "$IRM" --rpc-url "$RPC")
echo "    Result: $IRM_OK"

if [ "$IRM_OK" != "true" ]; then
  echo "ABORT: IRM $IRM is not enabled on Morpho."
  exit 1
fi

# ── Step 4: Compute Market ID ───────────────────────────────

echo "==> Computing market ID..."
ENCODED=$(cast abi-encode "x(address,address,address,address,uint256)" \
  "$LOAN_TOKEN" "$COLLATERAL_TOKEN" "$ORACLE" "$IRM" "$LLTV")
MARKET_ID=$(cast keccak "$ENCODED")
echo "    Market ID: $MARKET_ID"

# ── Step 5: Check if market already exists ──────────────────

echo "==> Checking if market already exists..."
LAST_UPDATE=$(cast call "$MORPHO" "market(bytes32)(uint128,uint128,uint128,uint128,uint128,uint128)" "$MARKET_ID" --rpc-url "$RPC" | head -1)
echo "    lastUpdate: $LAST_UPDATE"

if [ "$LAST_UPDATE" != "0" ]; then
  echo "Market already exists (lastUpdate=$LAST_UPDATE). Nothing to do."
  exit 0
fi

# ── Step 6: Send createMarket ───────────────────────────────

echo ""
echo "==> Sending createMarket transaction..."
echo "    loanToken:       $LOAN_TOKEN (USDC.e)"
echo "    collateralToken: $COLLATERAL_TOKEN (w0G)"
echo "    oracle:          $ORACLE"
echo "    irm:             $IRM"
echo "    lltv:            $LLTV (86%)"
echo ""

TX_HASH=$(cast send "$MORPHO" \
  "createMarket((address,address,address,address,uint256))" \
  "($LOAN_TOKEN,$COLLATERAL_TOKEN,$ORACLE,$IRM,$LLTV)" \
  --rpc-url "$RPC" \
  --private-key "$PRIVATE_KEY" \
  --legacy \
  --gas-price 5000000000 \
  --json | jq -r '.transactionHash')

echo "    Tx hash: $TX_HASH"

# ── Step 7: Verify market was created ───────────────────────

echo "==> Verifying market creation..."
sleep 3

LAST_UPDATE=$(cast call "$MORPHO" "market(bytes32)(uint128,uint128,uint128,uint128,uint128,uint128)" "$MARKET_ID" --rpc-url "$RPC" | head -1)
echo "    lastUpdate: $LAST_UPDATE"

if [ "$LAST_UPDATE" != "0" ]; then
  echo ""
  echo "SUCCESS — Market created."
  echo "  Market:    LONG — borrow USDC.e / collateral w0G / 86% LLTV"
  echo "  Market ID: $MARKET_ID"
  echo "  Oracle:    $ORACLE"
  echo "  Tx hash:   $TX_HASH"
  echo "  Explorer:  https://chainscan.0g.ai/tx/$TX_HASH"
else
  echo ""
  echo "WARNING — Market lastUpdate is still 0. Transaction may have reverted."
  echo "  Check: https://chainscan.0g.ai/tx/$TX_HASH"
  exit 1
fi
