#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd forge
require_cmd cast
require_var SEPOLIA_RPC_URL
require_address REACTIVE_ADDRESS
require_address GUARDIAN_ADDRESS
require_address SAFE_WALLET_ADDRESS
require_address SEPOLIA_CALLBACK_PROXY

init_signer

check_chain_id "$SEPOLIA_RPC_URL" "$SEPOLIA_CHAIN_ID" "Ethereum Sepolia"

echo "Deploying SafeSweepVault to Ethereum Sepolia..."
forge create src/SafeSweepVault.sol:SafeSweepVault \
  --rpc-url "$SEPOLIA_RPC_URL" \
  "${SIGNER_ARGS[@]}" \
  --broadcast \
  --constructor-args \
    "$SEPOLIA_CALLBACK_PROXY" \
    "$REACTIVE_ADDRESS" \
    "$GUARDIAN_ADDRESS" \
    "$SAFE_WALLET_ADDRESS"

echo
echo "Copy the deployed address into VAULT_ADDRESS in .env before continuing."
