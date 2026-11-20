#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd cast
require_var LASNA_RPC_URL
require_var SEPOLIA_RPC_URL
require_address REACTIVE_ADDRESS
require_address VAULT_ADDRESS
require_address REACTIVE_SYSTEM_ADDRESS
require_address SEPOLIA_CALLBACK_PROXY
require_uint REACTIVE_RESERVE_WEI
require_uint CALLBACK_RESERVE_WEI

init_signer

check_chain_id "$LASNA_RPC_URL" "$LASNA_CHAIN_ID" "Lasna"
check_chain_id "$SEPOLIA_RPC_URL" "$SEPOLIA_CHAIN_ID" "Ethereum Sepolia"

echo "Funding Reactive execution reserve..."
cast send "$REACTIVE_SYSTEM_ADDRESS" \
  "depositTo(address)" "$REACTIVE_ADDRESS" \
  --value "$REACTIVE_RESERVE_WEI" \
  --rpc-url "$LASNA_RPC_URL" \
  "${SIGNER_ARGS[@]}"

echo "Funding Sepolia callback reserve for the vault..."
cast send "$SEPOLIA_CALLBACK_PROXY" \
  "depositTo(address)" "$VAULT_ADDRESS" \
  --value "$CALLBACK_RESERVE_WEI" \
  --rpc-url "$SEPOLIA_RPC_URL" \
  "${SIGNER_ARGS[@]}"

echo "Service reserves funded."
