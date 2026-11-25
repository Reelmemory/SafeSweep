#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOLS_DIR="$ROOT_DIR/.tools/foundry-nightly"

if ! command -v forge >/dev/null 2>&1 && [[ -x "$TOOLS_DIR/forge" ]]; then
  export PATH="$TOOLS_DIR:$PATH"
fi
for cmd in forge cast anvil python3; do
  command -v "$cmd" >/dev/null 2>&1 || {
    echo "error: $cmd is required" >&2
    exit 127
  }
done

# The sandbox toolchain bundles Solar, which avoids outbound compiler downloads.
if [[ -z "${FOUNDRY_SOLC:-}" && -x "$TOOLS_DIR/solar" ]]; then
  export FOUNDRY_SOLC="$TOOLS_DIR/solar"
fi
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1
export SAFESWEEP_SKIP_DOTENV=1

LASNA_PORT="${SAFESWEEP_LOCAL_LASNA_PORT:-18545}"
SEPOLIA_PORT="${SAFESWEEP_LOCAL_SEPOLIA_PORT:-18546}"
export LASNA_RPC_URL="http://127.0.0.1:${LASNA_PORT}"
export BASE_SEPOLIA_RPC_URL="http://127.0.0.1:${SEPOLIA_PORT}"
export LASNA_CHAIN_ID=5318007
export BASE_SEPOLIA_CHAIN_ID=84532
export REACTIVE_SYSTEM_ADDRESS=0x8888888888888888888888888888888888888888
export BASE_SEPOLIA_CALLBACK_PROXY=0x476F44b11F5C942c58f4c8E3d0300E5710743585

# Standard Anvil account #0. Local rehearsal only; never use this key on a live network.
export PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
export GUARDIAN_ADDRESS=0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
export SAFE_WALLET_ADDRESS=0x70997970C51812dc3A010C7d01b50e0d17dc79C8
export REACTIVE_RESERVE_WEI=1000000000000000000
export CALLBACK_RESERVE_WEI=100000000000000000
export VAULT_DEMO_WEI=10000000000000000

TMP_DIR="$(mktemp -d)"
LASNA_PID=""
SEPOLIA_PID=""
cleanup() {
  [[ -n "$LASNA_PID" ]] && kill "$LASNA_PID" 2>/dev/null || true
  [[ -n "$SEPOLIA_PID" ]] && kill "$SEPOLIA_PID" 2>/dev/null || true
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

wait_rpc() {
  local rpc="$1"
  for _ in $(seq 1 50); do
    if cast chain-id --rpc-url "$rpc" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  echo "error: local RPC did not start: $rpc" >&2
  return 1
}

deployed_address() {
  awk '/Deployed to:/ {print $3}' "$1" | tail -1
}

tx_hash() {
  awk '/transactionHash/ {print $2}' "$1" | tail -1
}

cd "$ROOT_DIR"

echo "== boot local target chains =="
anvil --chain-id "$LASNA_CHAIN_ID" --port "$LASNA_PORT" --silent >"$TMP_DIR/lasna.log" 2>&1 &
LASNA_PID=$!
anvil --chain-id "$BASE_SEPOLIA_CHAIN_ID" --port "$SEPOLIA_PORT" --silent >"$TMP_DIR/sepolia.log" 2>&1 &
SEPOLIA_PID=$!
wait_rpc "$LASNA_RPC_URL"
wait_rpc "$BASE_SEPOLIA_RPC_URL"

echo "== install local Reactive system + callback proxy mocks =="
forge create test/mocks/MockSystem.sol:MockSystem \
  --rpc-url "$LASNA_RPC_URL" --private-key "$PRIVATE_KEY" --broadcast >"$TMP_DIR/mock-system.txt"
MOCK_SYSTEM="$(deployed_address "$TMP_DIR/mock-system.txt")"
forge create test/mocks/MockCallbackProxy.sol:MockCallbackProxy \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY" --broadcast >"$TMP_DIR/mock-proxy.txt"
MOCK_PROXY="$(deployed_address "$TMP_DIR/mock-proxy.txt")"

SYSTEM_CODE="$(cast code "$MOCK_SYSTEM" --rpc-url "$LASNA_RPC_URL")"
PROXY_CODE="$(cast code "$MOCK_PROXY" --rpc-url "$BASE_SEPOLIA_RPC_URL")"
cast rpc anvil_setCode "$REACTIVE_SYSTEM_ADDRESS" "$SYSTEM_CODE" --rpc-url "$LASNA_RPC_URL" >/dev/null
cast rpc anvil_setCode "$BASE_SEPOLIA_CALLBACK_PROXY" "$PROXY_CODE" --rpc-url "$BASE_SEPOLIA_RPC_URL" >/dev/null

echo "== deploy + wire SafeSweep with the live launcher =="
export SAFESWEEP_DEPLOYMENT_MANIFEST="$TMP_DIR/deployment.json"
./scripts/deploy/ship-live.sh >"$TMP_DIR/ship-live.txt"
export REACTIVE_ADDRESS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["reactive_contract"])' "$SAFESWEEP_DEPLOYMENT_MANIFEST")"
export VAULT_ADDRESS="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["vault_contract"])' "$SAFESWEEP_DEPLOYMENT_MANIFEST")"

[[ "$(cast call "$REACTIVE_ADDRESS" 'configured()(bool)' --rpc-url "$LASNA_RPC_URL")" == "true" ]]
[[ "$(cast balance "$VAULT_ADDRESS" --rpc-url "$BASE_SEPOLIA_RPC_URL")" == "$VAULT_DEMO_WEI" ]]

echo "== guardian panic =="
export INCIDENT_ID="$(cast keccak 'safesweep-local-rehearsal')"
SAFE_BEFORE="$(cast balance "$SAFE_WALLET_ADDRESS" --rpc-url "$BASE_SEPOLIA_RPC_URL")"
./scripts/deploy/07-panic.sh >"$TMP_DIR/panic.txt"
PANIC_TX="$(awk '/panic tx:/ {print $3}' "$TMP_DIR/panic.txt" | tail -1)"
[[ "$PANIC_TX" =~ ^0x[0-9a-fA-F]{64}$ ]]

echo "== simulate Reactive Network event delivery =="
TOPIC0="$(cast call "$REACTIVE_ADDRESS" 'PANIC_TOPIC_0()(uint256)' --rpc-url "$LASNA_RPC_URL" | awk '{print $1}')"
GUARDIAN_UINT="$(cast to-dec "$GUARDIAN_ADDRESS")"
cast rpc anvil_impersonateAccount "$REACTIVE_SYSTEM_ADDRESS" --rpc-url "$LASNA_RPC_URL" >/dev/null
cast rpc anvil_setBalance "$REACTIVE_SYSTEM_ADDRESS" 0x3635C9ADC5DEA00000 --rpc-url "$LASNA_RPC_URL" >/dev/null
LOG_TUPLE="($BASE_SEPOLIA_CHAIN_ID,$VAULT_ADDRESS,$TOPIC0,$GUARDIAN_UINT,$INCIDENT_ID,0,0x,0,3,0,$PANIC_TX,0)"
cast send "$REACTIVE_ADDRESS" \
  'react((uint256,address,uint256,uint256,uint256,uint256,bytes,uint256,uint256,uint256,uint256,uint256))' \
  "$LOG_TUPLE" \
  --rpc-url "$LASNA_RPC_URL" --from "$REACTIVE_SYSTEM_ADDRESS" --unlocked >"$TMP_DIR/react.txt"
REACTIVE_TX="$(tx_hash "$TMP_DIR/react.txt")"

[[ "$(cast call "$REACTIVE_SYSTEM_ADDRESS" 'callbackCount()(uint256)' --rpc-url "$LASNA_RPC_URL" | awk '{print $1}')" == "1" ]]
CALLBACK_RECIPIENT="$(cast call "$REACTIVE_SYSTEM_ADDRESS" 'lastCallbackRecipient()(address)' --rpc-url "$LASNA_RPC_URL")"
[[ "${VAULT_ADDRESS,,}" == "${CALLBACK_RECIPIENT,,}" ]]

echo "== simulate destination callback proxy =="
cast send "$BASE_SEPOLIA_CALLBACK_PROXY" \
  'deliver(address,address,bytes32)' "$VAULT_ADDRESS" "$REACTIVE_ADDRESS" "$INCIDENT_ID" \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" --private-key "$PRIVATE_KEY" >"$TMP_DIR/callback.txt"
CALLBACK_TX="$(tx_hash "$TMP_DIR/callback.txt")"

# The real Reactive system writes the destination transaction hash into its callback
# record after delivery. Mirror that bookkeeping so the evidence verifier itself
# is exercised during the local rehearsal.
cast send "$REACTIVE_SYSTEM_ADDRESS" \
  'setDeliveredCallbackTx(uint256)' "$CALLBACK_TX" \
  --rpc-url "$LASNA_RPC_URL" --private-key "$PRIVATE_KEY" >/dev/null

SAFE_AFTER="$(cast balance "$SAFE_WALLET_ADDRESS" --rpc-url "$BASE_SEPOLIA_RPC_URL")"
VAULT_AFTER="$(cast balance "$VAULT_ADDRESS" --rpc-url "$BASE_SEPOLIA_RPC_URL")"
SWEPT="$(cast call "$VAULT_ADDRESS" 'swept()(bool)' --rpc-url "$BASE_SEPOLIA_RPC_URL")"
DELTA="$(python3 -c 'import sys; print(int(sys.argv[2]) - int(sys.argv[1]))' "$SAFE_BEFORE" "$SAFE_AFTER")"

[[ "$DELTA" == "$VAULT_DEMO_WEI" ]]
[[ "$VAULT_AFTER" == "0" ]]
[[ "$SWEPT" == "true" ]]

echo "== verify three-link evidence pipeline =="
cast rpc anvil_mine 0xc --rpc-url "$BASE_SEPOLIA_RPC_URL" >/dev/null
./scripts/safesweep.sh proof >"$TMP_DIR/proof.txt"
python3 - "$SAFESWEEP_DEPLOYMENT_MANIFEST" <<'PY2'
import json, sys
data = json.load(open(sys.argv[1]))
assert data.get("proof_verified") is True
assert data.get("panic_tx")
assert data.get("reactive_tx")
assert data.get("callback_tx")
PY2

cat <<EOF

SafeSweep local rehearsal: PASS
  Reactive:      $REACTIVE_ADDRESS
  Vault:         $VAULT_ADDRESS
  Panic tx:      $PANIC_TX
  Reactive tx:   $REACTIVE_TX
  Callback tx:   $CALLBACK_TX
  Swept amount:  $DELTA wei
  Vault balance: $VAULT_AFTER
  swept:         $SWEPT

These are local Anvil transaction hashes, not submission evidence.
EOF
