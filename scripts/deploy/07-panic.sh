#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd cast
require_cmd python3
require_var SEPOLIA_RPC_URL
require_address VAULT_ADDRESS
require_address GUARDIAN_ADDRESS

init_signer

check_chain_id "$SEPOLIA_RPC_URL" "$SEPOLIA_CHAIN_ID" "Ethereum Sepolia"

signer="${SIGNER_ADDRESS}"
if [[ "${signer,,}" != "${GUARDIAN_ADDRESS,,}" ]]; then
  echo "error: configured signer is $signer, but vault guardian is $GUARDIAN_ADDRESS" >&2
  exit 1
fi

swept="$(cast call "$VAULT_ADDRESS" 'swept()(bool)' --rpc-url "$SEPOLIA_RPC_URL")"
if [[ "$swept" != "false" ]]; then
  echo "error: vault is already swept; refusing to trigger another incident" >&2
  exit 1
fi

INCIDENT_ID="${INCIDENT_ID:-$(cast keccak "safesweep-demo-$(date -u +%Y%m%dT%H%M%SZ)")}"

if [[ ! "$INCIDENT_ID" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
  echo "error: INCIDENT_ID must be a bytes32 hex value" >&2
  exit 1
fi

echo "Triggering guardian panic"
echo "guardian:    $GUARDIAN_ADDRESS"
echo "vault:       $VAULT_ADDRESS"
echo "incident id: $INCIDENT_ID"

PANIC_TX_HASH="$(cast send "$VAULT_ADDRESS" \
  "panic(bytes32)" "$INCIDENT_ID" \
  --rpc-url "$SEPOLIA_RPC_URL" \
  "${SIGNER_ARGS[@]}" \
  --async)"

if [[ ! "$PANIC_TX_HASH" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
  echo "error: cast did not return a transaction hash: $PANIC_TX_HASH" >&2
  exit 1
fi

echo "panic tx:    $PANIC_TX_HASH"
echo "waiting for Sepolia receipt..."
status="$(cast receipt "$PANIC_TX_HASH" status --rpc-url "$SEPOLIA_RPC_URL")"
if [[ "$status" != "1" && "$status" != "0x1" && "$status" != "true" ]]; then
  echo "error: panic transaction failed with status $status" >&2
  exit 1
fi

echo "panic receipt confirmed"

MANIFEST_PATH="${SAFESWEEP_DEPLOYMENT_MANIFEST:-}"
if [[ -z "$MANIFEST_PATH" ]]; then
  MANIFEST_PATH="$(ls -1t "$ROOT_DIR"/deployments/live-*.json 2>/dev/null | head -1 || true)"
fi

if [[ -n "$MANIFEST_PATH" && -f "$MANIFEST_PATH" ]]; then
  export MANIFEST_PATH PANIC_TX_HASH INCIDENT_ID
  python3 - <<'PY'
import json, os
from pathlib import Path
path = Path(os.environ["MANIFEST_PATH"])
data = json.loads(path.read_text())
data["incident_id"] = os.environ["INCIDENT_ID"]
data["panic_tx"] = os.environ["PANIC_TX_HASH"]
path.write_text(json.dumps(data, indent=2) + "\n")
PY
  echo "manifest updated: $MANIFEST_PATH"
else
  echo "note: no deployment manifest found; record panic tx manually" >&2
fi

echo
echo "Origin evidence captured. Next: locate the corresponding Lasna reactive transaction, then run:"
echo "  ./scripts/evidence/record-proof.sh <reactive-tx-hash> <callback-tx-hash>"
