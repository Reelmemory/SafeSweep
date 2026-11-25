#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd cast
require_var BASE_SEPOLIA_RPC_URL
require_address VAULT_ADDRESS
require_uint VAULT_DEMO_WEI

init_signer

check_chain_id "$BASE_SEPOLIA_RPC_URL" "$BASE_SEPOLIA_CHAIN_ID" "Base Sepolia"

echo "Funding protected vault with demo ETH..."
cast send "$VAULT_ADDRESS" \
  --value "$VAULT_DEMO_WEI" \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  "${SIGNER_ARGS[@]}"

echo "Vault funded."
