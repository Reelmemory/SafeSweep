#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

load_deployment
require_cmd cast
require_cmd python3
require_var BASE_SEPOLIA_RPC_URL
require_address VAULT_ADDRESS
require_address GUARDIAN_ADDRESS

init_signer

check_chain_id "$BASE_SEPOLIA_RPC_URL" "$BASE_SEPOLIA_CHAIN_ID" "Base Sepolia"

signer="${SIGNER_ADDRESS}"
if [[ "${signer,,}" != "${GUARDIAN_ADDRESS,,}" ]]; then
  echo "error: configured signer is $signer, but vault guardian is $GUARDIAN_ADDRESS" >&2
  exit 1
fi

swept="$(cast call "$VAULT_ADDRESS" 'swept()(bool)' --rpc-url "$BASE_SEPOLIA_RPC_URL")"
if [[ "$swept" != "false" ]]; then
  echo "error: vault is already swept; refusing to trigger another incident" >&2
  exit 1
fi

# Verify the deployed route and both fee accounts before the one live trigger.
verify_read() {
  local expected="$1" actual
  shift
  actual="$(cast call "$@" | awk '{print $1}')"
  [[ "${actual,,}" == "${expected,,}" ]] || { echo "unexpected contract state: $actual (expected $expected)" >&2; exit 1; }
}
verify_read "$GUARDIAN_ADDRESS" "$VAULT_ADDRESS" 'guardian()(address)' --rpc-url "$BASE_SEPOLIA_RPC_URL"
verify_read "$SAFE_WALLET_ADDRESS" "$VAULT_ADDRESS" 'safeWallet()(address)' --rpc-url "$BASE_SEPOLIA_RPC_URL"
verify_read "$REACTIVE_ADDRESS" "$VAULT_ADDRESS" '_CALLBACK_SENDER()(address)' --rpc-url "$BASE_SEPOLIA_RPC_URL"
verify_read "$BASE_SEPOLIA_CALLBACK_PROXY" "$VAULT_ADDRESS" '_SERVICE_PROVIDER()(address)' --rpc-url "$BASE_SEPOLIA_RPC_URL"
check_chain_id "$LASNA_RPC_URL" "$LASNA_CHAIN_ID" Lasna
verify_read true "$REACTIVE_ADDRESS" 'configured()(bool)' --rpc-url "$LASNA_RPC_URL"
for getter in originVault callbackRecipient; do
  verify_read "$VAULT_ADDRESS" "$REACTIVE_ADDRESS" "$getter()(address)" --rpc-url "$LASNA_RPC_URL"
done
for getter in originChainId destinationChainId; do
  verify_read 84532 "$REACTIVE_ADDRESS" "$getter()(uint256)" --rpc-url "$LASNA_RPC_URL"
done
check_service() {
  verify_read 0 "$1" 'debt(address)(uint256)' "$2" --rpc-url "$3"
  [[ "$(cast call "$1" 'reserves(address)(uint256)' "$2" --rpc-url "$3" | awk '{print $1}')" != 0 ]]
}
check_service "$REACTIVE_SYSTEM_ADDRESS" "$REACTIVE_ADDRESS" "$LASNA_RPC_URL"
check_service "$BASE_SEPOLIA_CALLBACK_PROXY" "$VAULT_ADDRESS" "$BASE_SEPOLIA_RPC_URL"
[[ "$(cast balance "$VAULT_ADDRESS" --rpc-url "$BASE_SEPOLIA_RPC_URL")" != 0 ]]
python3 - "$MANIFEST_PATH" <<'PYDATA'
import json, sys
if json.load(open(sys.argv[1])).get("panic_tx"):
    raise SystemExit("Panic already recorded for this deployment")
PYDATA

INCIDENT_ID="${INCIDENT_ID:-$(cast keccak "safesweep-demo-$(date -u +%Y%m%dT%H%M%SZ)")}"

if [[ ! "$INCIDENT_ID" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
  echo "error: INCIDENT_ID must be a bytes32 hex value" >&2
  exit 1
fi

echo "Triggering guardian panic"
echo "guardian:    $GUARDIAN_ADDRESS"
echo "vault:       $VAULT_ADDRESS"
echo "incident id: $INCIDENT_ID"

export LASNA_START_BLOCK="$(cast block-number --rpc-url "$LASNA_RPC_URL")"
PANIC_TX_HASH="$(cast send "$VAULT_ADDRESS" \
  "panic(bytes32)" "$INCIDENT_ID" \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  "${SIGNER_ARGS[@]}" \
  --async)"

if [[ ! "$PANIC_TX_HASH" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
  echo "error: cast did not return a transaction hash: $PANIC_TX_HASH" >&2
  exit 1
fi

echo "panic tx:    $PANIC_TX_HASH"
echo "waiting for Base Sepolia receipt..."
status="$(cast receipt "$PANIC_TX_HASH" status --rpc-url "$BASE_SEPOLIA_RPC_URL")"
if [[ "$status" != "1" && "$status" != "0x1" && "$status" != "true" ]]; then
  echo "error: panic transaction failed with status $status" >&2
  exit 1
fi

echo "panic receipt confirmed"



if [[ -n "$MANIFEST_PATH" && -f "$MANIFEST_PATH" ]]; then
  export MANIFEST_PATH PANIC_TX_HASH INCIDENT_ID
  python3 - <<'PY'
import json, os
from pathlib import Path
path = Path(os.environ["MANIFEST_PATH"])
data = json.loads(path.read_text())
data["incident_id"] = os.environ["INCIDENT_ID"]
data["lasna_start_block"] = int(os.environ["LASNA_START_BLOCK"])
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
