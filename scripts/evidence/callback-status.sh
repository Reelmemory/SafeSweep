#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../deploy/common.sh"

require_cmd cast
require_var LASNA_RPC_URL
require_address REACTIVE_SYSTEM_ADDRESS

REACTIVE_TX_HASH="${1:-${REACTIVE_TX_HASH:-}}"
if [[ ! "$REACTIVE_TX_HASH" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
  echo "usage: $0 0x<reactive-transaction-hash>" >&2
  exit 1
fi

check_chain_id "$LASNA_RPC_URL" "$LASNA_CHAIN_ID" "Lasna"

cast call "$REACTIVE_SYSTEM_ADDRESS" \
  "getCallbacks(uint256)((uint256,address,uint256,uint256,uint256,bytes)[])" \
  "$REACTIVE_TX_HASH" \
  --rpc-url "$LASNA_RPC_URL"
