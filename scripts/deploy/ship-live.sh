#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd forge
require_cmd cast
require_cmd python3
require_var SEPOLIA_RPC_URL
require_var LASNA_RPC_URL
require_address GUARDIAN_ADDRESS
require_address SAFE_WALLET_ADDRESS
require_address REACTIVE_SYSTEM_ADDRESS
require_address SEPOLIA_CALLBACK_PROXY
require_uint REACTIVE_RESERVE_WEI
require_uint CALLBACK_RESERVE_WEI
require_uint VAULT_DEMO_WEI

init_signer

# Child scripts should use this process's already-loaded environment. This avoids
# stale blank REACTIVE_ADDRESS/VAULT_ADDRESS entries in .env overwriting values
# captured from the deployments below.
export SAFESWEEP_SKIP_DOTENV=1

TMP_DIR="$(mktemp -d)"
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT INT TERM

deployed_address() {
  awk '/Deployed to:/ {print $3}' "$1" | tail -1
}

assert_code() {
  local address="$1"
  local rpc="$2"
  local label="$3"
  local code
  code="$(cast code "$address" --rpc-url "$rpc")"
  if [[ "$code" == "0x" ]]; then
    echo "error: no code found for $label at $address" >&2
    exit 1
  fi
}

check_funding_floor() {
  local deployer lasna_balance sepolia_balance sepolia_floor
  deployer="${SIGNER_ADDRESS}"
  lasna_balance="$(cast balance "$deployer" --rpc-url "$LASNA_RPC_URL")"
  sepolia_balance="$(cast balance "$deployer" --rpc-url "$SEPOLIA_RPC_URL")"
  sepolia_floor="$(python3 -c 'import sys; print(int(sys.argv[1]) + int(sys.argv[2]))' "$CALLBACK_RESERVE_WEI" "$VAULT_DEMO_WEI")"

  echo "deployer Lasna balance:   $lasna_balance wei"
  echo "deployer Sepolia balance: $sepolia_balance wei"

  python3 - "$lasna_balance" "$REACTIVE_RESERVE_WEI" "$sepolia_balance" "$sepolia_floor" <<'PY'
import sys
lasna, lasna_floor, sepolia, sepolia_floor = map(int, sys.argv[1:])
if lasna <= lasna_floor:
    raise SystemExit("error: Lasna balance must exceed REACTIVE_RESERVE_WEI so gas remains available")
if sepolia <= sepolia_floor:
    raise SystemExit("error: Sepolia balance must exceed callback reserve + demo vault funding so gas remains available")
PY
}

echo "== SafeSweep live deployment preflight =="
./scripts/deploy/00-preflight.sh
check_funding_floor

echo
echo "== 1/5 deploy Reactive contract to Lasna =="
./scripts/deploy/01-deploy-reactive.sh | tee "$TMP_DIR/reactive.txt"
export REACTIVE_ADDRESS="$(deployed_address "$TMP_DIR/reactive.txt")"
require_address REACTIVE_ADDRESS
assert_code "$REACTIVE_ADDRESS" "$LASNA_RPC_URL" "SafeSweepReactive"

echo
echo "== 2/5 deploy protected vault to Sepolia =="
./scripts/deploy/02-deploy-vault.sh | tee "$TMP_DIR/vault.txt"
export VAULT_ADDRESS="$(deployed_address "$TMP_DIR/vault.txt")"
require_address VAULT_ADDRESS
assert_code "$VAULT_ADDRESS" "$SEPOLIA_RPC_URL" "SafeSweepVault"

echo
echo "== 3/5 configure Reactive subscription =="
./scripts/deploy/03-configure-reactive.sh

echo
echo "== 4/5 fund execution + callback reserves =="
./scripts/deploy/04-fund-services.sh

echo
echo "== 5/5 fund protected demo vault =="
./scripts/deploy/05-fund-vault.sh

echo
echo "== final status =="
./scripts/deploy/06-status.sh

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
MANIFEST_PATH="${SAFESWEEP_DEPLOYMENT_MANIFEST:-$ROOT_DIR/deployments/live-${TIMESTAMP}.json}"
mkdir -p "$(dirname "$MANIFEST_PATH")"
export TIMESTAMP MANIFEST_PATH
export SEPOLIA_CHAIN_ID LASNA_CHAIN_ID REACTIVE_SYSTEM_ADDRESS SEPOLIA_CALLBACK_PROXY
export REACTIVE_ADDRESS VAULT_ADDRESS GUARDIAN_ADDRESS SAFE_WALLET_ADDRESS

python3 - <<'PY'
import json, os
from pathlib import Path
payload = {
    "project": "SafeSweep",
    "deployed_at_utc": os.environ["TIMESTAMP"],
    "origin": {"name": "Ethereum Sepolia", "chain_id": int(os.environ["SEPOLIA_CHAIN_ID"])},
    "reactive_network": {"name": "Reactive Lasna", "chain_id": int(os.environ["LASNA_CHAIN_ID"])},
    "reactive_system": os.environ["REACTIVE_SYSTEM_ADDRESS"],
    "callback_proxy": os.environ["SEPOLIA_CALLBACK_PROXY"],
    "reactive_contract": os.environ["REACTIVE_ADDRESS"],
    "vault_contract": os.environ["VAULT_ADDRESS"],
    "guardian": os.environ["GUARDIAN_ADDRESS"],
    "safe_wallet": os.environ["SAFE_WALLET_ADDRESS"],
    "panic_tx": None,
    "reactive_tx": None,
    "callback_tx": None,
}
path = Path(os.environ["MANIFEST_PATH"])
path.write_text(json.dumps(payload, indent=2) + "\n")
PY

echo
echo "SafeSweep contracts are deployed, configured, and funded."
echo "Reactive: $REACTIVE_ADDRESS"
echo "Vault:    $VAULT_ADDRESS"
echo "Manifest: $MANIFEST_PATH"
echo
echo "Panic is intentionally NOT triggered by this script."
echo "When ready to create submission evidence, run ./scripts/safesweep.sh panic with the guardian signer."
