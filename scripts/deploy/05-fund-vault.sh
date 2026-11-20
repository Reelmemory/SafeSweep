#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd cast
require_var SEPOLIA_RPC_URL
require_address VAULT_ADDRESS
require_uint VAULT_DEMO_WEI

init_signer

check_chain_id "$SEPOLIA_RPC_URL" "$SEPOLIA_CHAIN_ID" "Ethereum Sepolia"

echo "Funding protected vault with demo ETH..."
cast send "$VAULT_ADDRESS" \
  --value "$VAULT_DEMO_WEI" \
  --rpc-url "$SEPOLIA_RPC_URL" \
  "${SIGNER_ARGS[@]}"

echo "Vault funded."
