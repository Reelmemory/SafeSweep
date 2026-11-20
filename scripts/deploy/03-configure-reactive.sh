#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd cast
require_var LASNA_RPC_URL
require_address REACTIVE_ADDRESS
require_address VAULT_ADDRESS

init_signer

check_chain_id "$LASNA_RPC_URL" "$LASNA_CHAIN_ID" "Lasna"

echo "Configuring SafeSweepReactive subscription + callback target..."
cast send "$REACTIVE_ADDRESS" \
  "configure(uint256,address,uint256,address)" \
  "$SEPOLIA_CHAIN_ID" \
  "$VAULT_ADDRESS" \
  "$SEPOLIA_CHAIN_ID" \
  "$VAULT_ADDRESS" \
  --rpc-url "$LASNA_RPC_URL" \
  "${SIGNER_ARGS[@]}"

echo "Reactive configuration submitted."
