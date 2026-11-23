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

check_chain_id "$LASNA_RPC_URL" "$LASNA_CHAIN_ID" "Lasna"
check_chain_id "$BASE_SEPOLIA_RPC_URL" "$BASE_SEPOLIA_CHAIN_ID" "Base Sepolia"

echo "== Reactive contract =="
echo "address: $REACTIVE_ADDRESS"
echo -n "balance: "
cast balance "$REACTIVE_ADDRESS" --rpc-url "$LASNA_RPC_URL"
echo -n "debt: "
cast call "$REACTIVE_SYSTEM_ADDRESS" "debt(address)(uint256)" "$REACTIVE_ADDRESS" --rpc-url "$LASNA_RPC_URL"
echo -n "reserves: "
cast call "$REACTIVE_SYSTEM_ADDRESS" "reserves(address)(uint256)" "$REACTIVE_ADDRESS" --rpc-url "$LASNA_RPC_URL"

echo
echo "== Vault / callback recipient =="
echo "address: $VAULT_ADDRESS"
echo -n "protected balance: "
cast balance "$VAULT_ADDRESS" --rpc-url "$BASE_SEPOLIA_RPC_URL"
echo -n "callback debt: "
cast call "$BASE_SEPOLIA_CALLBACK_PROXY" "debt(address)(uint256)" "$VAULT_ADDRESS" --rpc-url "$BASE_SEPOLIA_RPC_URL"
echo -n "callback reserves: "
cast call "$BASE_SEPOLIA_CALLBACK_PROXY" "reserves(address)(uint256)" "$VAULT_ADDRESS" --rpc-url "$BASE_SEPOLIA_RPC_URL"
echo -n "swept: "
cast call "$VAULT_ADDRESS" "swept()(bool)" --rpc-url "$BASE_SEPOLIA_RPC_URL"
