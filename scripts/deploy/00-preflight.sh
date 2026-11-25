#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd forge
require_cmd cast
require_var BASE_SEPOLIA_RPC_URL
require_var LASNA_RPC_URL
require_address GUARDIAN_ADDRESS
require_address SAFE_WALLET_ADDRESS
require_address REACTIVE_SYSTEM_ADDRESS
require_address BASE_SEPOLIA_CALLBACK_PROXY

if [[ -n "${SEPOLIA_CHAIN_ID:-}" && -z "${BASE_MIGRATION_REVIEWED:-}" ]]; then
  echo "Old Ethereum Sepolia .env detected. Use .env.example and copy the intended guardian and safe wallet." >&2
  exit 1
fi

init_signer

check_chain_id "$LASNA_RPC_URL" "$LASNA_CHAIN_ID" "Lasna"
check_chain_id "$BASE_SEPOLIA_RPC_URL" "$BASE_SEPOLIA_CHAIN_ID" "Base Sepolia"

system_code="$(cast code "$REACTIVE_SYSTEM_ADDRESS" --rpc-url "$LASNA_RPC_URL")"
proxy_code="$(cast code "$BASE_SEPOLIA_CALLBACK_PROXY" --rpc-url "$BASE_SEPOLIA_RPC_URL")"

if [[ "$system_code" == "0x" ]]; then
  echo "error: no code at Reactive system address" >&2
  exit 1
fi
if [[ "$proxy_code" == "0x" ]]; then
  echo "error: no code at Base Sepolia callback proxy" >&2
  exit 1
fi

echo "ok: Reactive system contract has code"
echo "ok: Base Sepolia callback proxy has code"

deployer="${SIGNER_ADDRESS}"
echo "deployer:    $deployer"
echo "guardian:    $GUARDIAN_ADDRESS"
echo "safe wallet: $SAFE_WALLET_ADDRESS"

if [[ "${deployer,,}" != "${GUARDIAN_ADDRESS,,}" ]]; then
  echo "note: deployer and guardian differ; the panic command must use the guardian signer"
fi

if [[ "${GUARDIAN_ADDRESS,,}" == "${SAFE_WALLET_ADDRESS,,}" ]]; then
  echo "error: guardian and safe wallet must be different demo roles" >&2
  exit 1
fi

# The v0 live demo deliberately uses an EOA safe wallet. Contract wallets can
# reject native ETH; that would make the callback fail and still incur fees.
safe_wallet_code="$(cast code "$SAFE_WALLET_ADDRESS" --rpc-url "$BASE_SEPOLIA_RPC_URL")"
if [[ "$safe_wallet_code" != "0x" ]]; then
  echo "error: SafeSweep v0 demo safe wallet must be an EOA (no deployed code)" >&2
  exit 1
fi
echo "ok: safe wallet is an EOA"

echo "preflight passed"
