#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd forge
require_cmd cast
require_var BASE_SEPOLIA_RPC_URL
require_address REACTIVE_ADDRESS
require_address GUARDIAN_ADDRESS
require_address SAFE_WALLET_ADDRESS
require_address BASE_SEPOLIA_CALLBACK_PROXY

init_signer

check_chain_id "$BASE_SEPOLIA_RPC_URL" "$BASE_SEPOLIA_CHAIN_ID" "Base Sepolia"

echo "Deploying SafeSweepVault to Base Sepolia..."
forge create src/SafeSweepVault.sol:SafeSweepVault \
  --rpc-url "$BASE_SEPOLIA_RPC_URL" \
  "${SIGNER_ARGS[@]}" \
  --broadcast \
  --constructor-args \
    "$BASE_SEPOLIA_CALLBACK_PROXY" \
    "$REACTIVE_ADDRESS" \
    "$GUARDIAN_ADDRESS" \
    "$SAFE_WALLET_ADDRESS"

echo
echo "Copy the deployed address into VAULT_ADDRESS in .env before continuing."
