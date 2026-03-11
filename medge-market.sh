#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# Create Morpho Blue Market — borrow USDC.e / collateral mEDGE
# LLTV: 96.5%
# ──────────────────────────────────────────────────────────────

RPC="https://evmrpc.0g.ai"
MORPHO="0x9CDD13a2212D94C4f12190cA30783B743E83C89e"

LOAN_TOKEN="0x1f3aa82227281ca364bfb3d253b0f1af1da6473e"       # USDC.e (6 decimals)
COLLATERAL_TOKEN="0xa1027783fc183a150126b094037a5eb2f5db30ba"  # mEDGE (18 decimals)
IRM="0xf52e20c42fec624819d4184226c4777d7cbd767e"
LLTV="965000000000000000"

if [ -z "${1:-}" ]; then
  echo "ERROR: Oracle address required."
  echo "  Usage: ./medge-market.sh <ORACLE_ADDRESS>"
  echo "  Deploy the oracle first: ./deploy-oracle-medge.sh"
  exit 1
fi

ORACLE="$1"

if [ -z "${PRIVATE_KEY:-}" ]; then
  echo "ERROR: PRIVATE_KEY env var is not set."
  echo "  export PRIVATE_KEY=0x..."
  exit 1
fi

# Verify oracle responds
echo "==> Verifying oracle at $ORACLE..."
ORACLE_PRICE=$(cast call "$ORACLE" "price()(uint256)" --rpc-url "$RPC" 2>&1) || {
  echo "ABORT: Oracle at $ORACLE does not respond to price(). Is this the right address?"
  exit 1
}
echo "    Oracle price (raw): $ORACLE_PRICE"

# Check LLTV enabled
echo "==> Checking isLltvEnabled($LLTV)..."
LLTV_OK=$(cast call "$MORPHO" "isLltvEnabled(uint256)(bool)" "$LLTV" --rpc-url "$RPC")
echo "    Result: $LLTV_OK"

if [ "$LLTV_OK" != "true" ]; then
  echo "ABORT: LLTV $LLTV is not enabled on Morpho. Need to enableLltv first."
  exit 1
fi

# Check IRM enabled
echo "==> Checking isIrmEnabled($IRM)..."
IRM_OK=$(cast call "$MORPHO" "isIrmEnabled(address)(bool)" "$IRM" --rpc-url "$RPC")
echo "    Result: $IRM_OK"

if [ "$IRM_OK" != "true" ]; then
  echo "ABORT: IRM $IRM is not enabled on Morpho."
  exit 1
fi

# Compute Market ID
echo "==> Computing market ID..."
ENCODED=$(cast abi-encode "x(address,address,address,address,uint256)" \
  "$LOAN_TOKEN" "$COLLATERAL_TOKEN" "$ORACLE" "$IRM" "$LLTV")
MARKET_ID=$(cast keccak "$ENCODED")
echo "    Market ID: $MARKET_ID"

# Check if market already exists
echo "==> Checking if market already exists..."
LAST_UPDATE=$(cast call "$MORPHO" "market(bytes32)(uint128,uint128,uint128,uint128,uint128,uint128)" "$MARKET_ID" --rpc-url "$RPC" | head -1)

if [ "$LAST_UPDATE" != "0" ]; then
  echo "Market already exists (lastUpdate=$LAST_UPDATE). Nothing to do."
  exit 0
fi

# Send createMarket
echo ""
echo "==> Sending createMarket transaction..."
echo "    loanToken:       $LOAN_TOKEN (USDC.e)"
echo "    collateralToken: $COLLATERAL_TOKEN (mEDGE)"
echo "    oracle:          $ORACLE"
echo "    irm:             $IRM"
echo "    lltv:            $LLTV (96.5%)"
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

# Verify market was created
echo "==> Verifying market creation..."
sleep 3

LAST_UPDATE=$(cast call "$MORPHO" "market(bytes32)(uint128,uint128,uint128,uint128,uint128,uint128)" "$MARKET_ID" --rpc-url "$RPC" | head -1)

if [ "$LAST_UPDATE" != "0" ]; then
  echo ""
  echo "SUCCESS — Market created."
  echo "  Market:    mEDGE/USDC.e — borrow USDC.e / collateral mEDGE / 96.5% LLTV"
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
