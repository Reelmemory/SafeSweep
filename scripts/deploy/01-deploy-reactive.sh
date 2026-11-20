#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd forge
require_cmd cast
require_var LASNA_RPC_URL

init_signer

check_chain_id "$LASNA_RPC_URL" "$LASNA_CHAIN_ID" "Lasna"

echo "Deploying SafeSweepReactive to Lasna..."
forge create src/SafeSweepReactive.sol:SafeSweepReactive \
  --rpc-url "$LASNA_RPC_URL" \
  "${SIGNER_ARGS[@]}" \
  --broadcast

echo
echo "Copy the deployed address into REACTIVE_ADDRESS in .env before continuing."
