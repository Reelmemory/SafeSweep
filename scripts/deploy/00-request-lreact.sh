#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

require_cmd cast
require_var SEPOLIA_RPC_URL
require_address SEPOLIA_REACTIVE_FAUCET

init_signer

LREACT_FAUCET_WEI="${LREACT_FAUCET_WEI:-100000000000000000}"
require_uint LREACT_FAUCET_WEI

recipient="${LREACT_RECIPIENT:-${SIGNER_ADDRESS}}" 
if [[ ! "$recipient" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
  echo "error: LREACT_RECIPIENT is not a valid EVM address" >&2
  exit 1
fi

check_chain_id "$SEPOLIA_RPC_URL" 11155111 "Ethereum Sepolia"

echo "Requesting Lasna lREACT for $recipient via the Sepolia Reactive faucet..."
echo "Sepolia ETH sent to faucet: $LREACT_FAUCET_WEI wei"
cast send "$SEPOLIA_REACTIVE_FAUCET" \
  "request(address)" "$recipient" \
  --value "$LREACT_FAUCET_WEI" \
  --rpc-url "$SEPOLIA_RPC_URL" \
  "${SIGNER_ARGS[@]}"

echo "Faucet request submitted. Check the recipient on Lasna before running ship-live.sh."
