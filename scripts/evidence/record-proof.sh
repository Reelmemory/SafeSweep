#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../deploy/common.sh"

load_deployment
require_cmd cast
require_cmd python3
require_var LASNA_RPC_URL
require_var BASE_SEPOLIA_RPC_URL
require_address REACTIVE_SYSTEM_ADDRESS
require_address VAULT_ADDRESS

REACTIVE_TX_HASH="${1:-${REACTIVE_TX_HASH:-}}"
CALLBACK_TX_HASH="${2:-${CALLBACK_TX_HASH:-}}"

for name in REACTIVE_TX_HASH CALLBACK_TX_HASH; do
  value="${!name:-}"
  if [[ ! "$value" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
    echo "usage: $0 0x<reactive-tx-hash> 0x<callback-tx-hash>" >&2
    exit 1
  fi
done

check_chain_id "$LASNA_RPC_URL" "$LASNA_CHAIN_ID" "Lasna"
check_chain_id "$BASE_SEPOLIA_RPC_URL" "$BASE_SEPOLIA_CHAIN_ID" "Base Sepolia"


if [[ -z "$MANIFEST_PATH" || ! -f "$MANIFEST_PATH" ]]; then
  echo "error: deployment manifest not found; set SAFESWEEP_DEPLOYMENT_MANIFEST" >&2
  exit 1
fi

export BASE_SEPOLIA_RPC_URL LASNA_RPC_URL
python3 "$ROOT_DIR/scripts/evidence/verify.py" "$MANIFEST_PATH" "$REACTIVE_TX_HASH" "$CALLBACK_TX_HASH"
echo "proof verified: $MANIFEST_PATH"
