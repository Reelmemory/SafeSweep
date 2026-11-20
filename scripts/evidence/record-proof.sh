#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/../deploy/common.sh"

require_cmd cast
require_cmd python3
require_var LASNA_RPC_URL
require_var SEPOLIA_RPC_URL
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
check_chain_id "$SEPOLIA_RPC_URL" "$SEPOLIA_CHAIN_ID" "Ethereum Sepolia"

MANIFEST_PATH="${SAFESWEEP_DEPLOYMENT_MANIFEST:-}"
if [[ -z "$MANIFEST_PATH" ]]; then
  MANIFEST_PATH="$(ls -1t "$ROOT_DIR"/deployments/live-*.json 2>/dev/null | head -1 || true)"
fi
if [[ -z "$MANIFEST_PATH" || ! -f "$MANIFEST_PATH" ]]; then
  echo "error: deployment manifest not found; set SAFESWEEP_DEPLOYMENT_MANIFEST" >&2
  exit 1
fi

PANIC_TX_HASH="$(python3 - "$MANIFEST_PATH" <<'PY'
import json, sys
print(json.load(open(sys.argv[1])).get("panic_tx") or "")
PY
)"
if [[ ! "$PANIC_TX_HASH" =~ ^0x[0-9a-fA-F]{64}$ ]]; then
  echo "error: manifest does not contain a valid panic_tx; run 07-panic.sh first" >&2
  exit 1
fi

check_receipt() {
  local label="$1" hash="$2" rpc="$3"
  local status
  status="$(cast receipt "$hash" status --rpc-url "$rpc")"
  if [[ "$status" != "1" && "$status" != "0x1" && "$status" != "true" ]]; then
    echo "error: $label receipt status is $status" >&2
    exit 1
  fi
  echo "ok: $label receipt confirmed ($hash)"
}

check_receipt "origin panic" "$PANIC_TX_HASH" "$SEPOLIA_RPC_URL"
check_receipt "Reactive" "$REACTIVE_TX_HASH" "$LASNA_RPC_URL"
check_receipt "destination callback" "$CALLBACK_TX_HASH" "$SEPOLIA_RPC_URL"

swept="$(cast call "$VAULT_ADDRESS" 'swept()(bool)' --rpc-url "$SEPOLIA_RPC_URL")"
balance="$(cast balance "$VAULT_ADDRESS" --rpc-url "$SEPOLIA_RPC_URL")"
if [[ "$swept" != "true" ]]; then
  echo "error: vault swept() is $swept; expected true" >&2
  exit 1
fi
if [[ "$balance" != "0" ]]; then
  echo "error: vault balance is $balance wei; expected 0" >&2
  exit 1
fi

echo "ok: vault reports swept=true and balance=0"

echo "checking callback record on Reactive system..."
callback_record="$(cast call "$REACTIVE_SYSTEM_ADDRESS" \
  'getCallbacks(uint256)((uint256,address,uint256,uint256,uint256,bytes)[])' \
  "$REACTIVE_TX_HASH" \
  --rpc-url "$LASNA_RPC_URL")"
if [[ -z "$callback_record" || "$callback_record" == "[]" ]]; then
  echo "error: Reactive system has no callback record for $REACTIVE_TX_HASH" >&2
  exit 1
fi
callback_tx_decimal="$(cast to-dec "$CALLBACK_TX_HASH")"
if [[ "${callback_record,,}" != *"${CALLBACK_TX_HASH#0x}"* && "$callback_record" != *"$callback_tx_decimal"* ]]; then
  echo "error: callback record exists but does not contain the supplied destination transaction hash" >&2
  echo "$callback_record" >&2
  exit 1
else
  echo "ok: Reactive callback record contains the destination transaction hash"
fi

export MANIFEST_PATH REACTIVE_TX_HASH CALLBACK_TX_HASH
python3 - <<'PY'
import json, os
from pathlib import Path
path = Path(os.environ["MANIFEST_PATH"])
data = json.loads(path.read_text())
data["reactive_tx"] = os.environ["REACTIVE_TX_HASH"]
data["callback_tx"] = os.environ["CALLBACK_TX_HASH"]
data["proof_verified"] = True
path.write_text(json.dumps(data, indent=2) + "\n")
PY

echo "proof manifest finalized: $MANIFEST_PATH"
