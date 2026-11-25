#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd cast
require_var LASNA_RPC_URL
require_var BASE_SEPOLIA_RPC_URL
require_address REACTIVE_ADDRESS
require_address VAULT_ADDRESS
require_address REACTIVE_SYSTEM_ADDRESS
require_address BASE_SEPOLIA_CALLBACK_PROXY
require_uint REACTIVE_RESERVE_WEI
require_uint CALLBACK_RESERVE_WEI

init_signer

check_chain_id "$LASNA_RPC_URL" "$LASNA_CHAIN_ID" "Lasna"
check_chain_id "$BASE_SEPOLIA_RPC_URL" "$BASE_SEPOLIA_CHAIN_ID" "Base Sepolia"

echo "Funding Reactive execution reserve..."
cast send "$REACTIVE_SYSTEM_ADDRESS" \
  "depositTo(address)" "$REACTIVE_ADDRESS" \
  --value "$REACTIVE_RESERVE_WEI" \
  --rpc-url "$LASNA_RPC_URL" \
  "${SIGNER_ARGS[@]}"

echo "Funding Base Sepolia callback reserve for the vault..."
cast send "$BASE_SEPOLIA_CALLBACK_PROXY" \
  "depositTo(address)" "$VAULT_ADDRESS" \
  --value "$CALLBACK_RESERVE_WEI" \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  "${SIGNER_ARGS[@]}"

echo "Service reserves funded."
