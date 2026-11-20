#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd forge
require_cmd cast
require_var SEPOLIA_RPC_URL
require_var LASNA_RPC_URL
require_address GUARDIAN_ADDRESS
require_address SAFE_WALLET_ADDRESS
require_address REACTIVE_SYSTEM_ADDRESS
require_address SEPOLIA_CALLBACK_PROXY

init_signer

check_chain_id "$LASNA_RPC_URL" "$LASNA_CHAIN_ID" "Lasna"
check_chain_id "$SEPOLIA_RPC_URL" "$SEPOLIA_CHAIN_ID" "Ethereum Sepolia"

system_code="$(cast code "$REACTIVE_SYSTEM_ADDRESS" --rpc-url "$LASNA_RPC_URL")"
proxy_code="$(cast code "$SEPOLIA_CALLBACK_PROXY" --rpc-url "$SEPOLIA_RPC_URL")"

if [[ "$system_code" == "0x" ]]; then
  echo "error: no code at Reactive system address" >&2
  exit 1
fi
if [[ "$proxy_code" == "0x" ]]; then
  echo "error: no code at Sepolia callback proxy" >&2
  exit 1
fi

echo "ok: Reactive system contract has code"
echo "ok: Sepolia callback proxy has code"

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
safe_wallet_code="$(cast code "$SAFE_WALLET_ADDRESS" --rpc-url "$SEPOLIA_RPC_URL")"
if [[ "$safe_wallet_code" != "0x" ]]; then
  echo "error: SafeSweep v0 demo safe wallet must be an EOA (no deployed code)" >&2
  exit 1
fi
echo "ok: safe wallet is an EOA"

echo "preflight passed"
