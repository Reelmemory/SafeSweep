#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [[ "${SAFESWEEP_SKIP_DOTENV:-0}" != "1" && -f "$ROOT_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  set -a
  source "$ROOT_DIR/.env"
  set +a
fi

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: required command '$1' not found" >&2
    exit 1
  }
}

require_var() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "error: required environment variable '$name' is empty" >&2
    exit 1
  fi
}

require_address() {
  local name="$1"
  require_var "$name"
  if [[ ! "${!name}" =~ ^0x[0-9a-fA-F]{40}$ || "${!name}" =~ ^0x0{40}$ ]]; then
    echo "error: '$name' is not a valid EVM address" >&2
    exit 1
  fi
}

require_uint() {
  local name="$1"
  require_var "$name"
  if [[ ! "${!name}" =~ ^[0-9]+$ ]]; then
    echo "error: '$name' must be an unsigned integer" >&2
    exit 1
  fi
}

init_signer() {
  SIGNER_ARGS=()
  SIGNER_ADDRESS=""

  if [[ -n "${PRIVATE_KEY:-}" ]]; then
    SIGNER_ARGS=(--private-key "$PRIVATE_KEY")
    SIGNER_ADDRESS="$(cast wallet address --private-key "$PRIVATE_KEY")"
    return 0
  fi

  if [[ -n "${SAFESWEEP_ACCOUNT:-}" ]]; then
    SIGNER_ARGS=(--account "$SAFESWEEP_ACCOUNT")
    if [[ -n "${SAFESWEEP_PASSWORD_FILE:-}" ]]; then
      if [[ ! -f "$SAFESWEEP_PASSWORD_FILE" ]]; then
        echo "error: SAFESWEEP_PASSWORD_FILE does not exist: $SAFESWEEP_PASSWORD_FILE" >&2
        exit 1
      fi
      SIGNER_ARGS+=(--password-file "$SAFESWEEP_PASSWORD_FILE")
    fi
    SIGNER_ADDRESS="$(cast wallet address "${SIGNER_ARGS[@]}")"
    return 0
  fi

  echo "error: configure a signer with SAFESWEEP_ACCOUNT (recommended) or PRIVATE_KEY (testnet automation only)" >&2
  exit 1
}

load_defaults() {
  : "${BASE_SEPOLIA_RPC_URL:=https://sepolia.base.org}"
  : "${LASNA_RPC_URL:=https://lasna-rpc.rnk.dev/}"
  : "${BASE_SEPOLIA_CHAIN_ID:=84532}"
  : "${LASNA_CHAIN_ID:=5318007}"
  : "${REACTIVE_SYSTEM_ADDRESS:=0x8888888888888888888888888888888888888888}"
  : "${BASE_SEPOLIA_CALLBACK_PROXY:=0x476F44b11F5C942c58f4c8E3d0300E5710743585}"
  : "${SEPOLIA_REACTIVE_FAUCET:=0x9b9BB25f1A81078C544C829c5EB7822d747Cf434}"
  : "${REACTIVE_RESERVE_WEI:=500000000000000000}"
  : "${CALLBACK_RESERVE_WEI:=2000000000000000}"
  : "${VAULT_DEMO_WEI:=5000000000000000}"
}

check_chain_id() {
  local rpc="$1"
  local expected="$2"
  local label="$3"
  local actual
  actual="$(cast chain-id --rpc-url "$rpc")"
  if [[ "$actual" != "$expected" ]]; then
    echo "error: $label RPC chain id is $actual; expected $expected" >&2
    exit 1
  fi
  echo "ok: $label chain id $actual"
}

load_defaults
export BASE_SEPOLIA_RPC_URL LASNA_RPC_URL
if [[ "$BASE_SEPOLIA_CHAIN_ID" != 84532 || "$LASNA_CHAIN_ID" != 5318007 || "${BASE_SEPOLIA_CALLBACK_PROXY,,}" != 0x476f44b11f5c942c58f4c8e3d0300e5710743585 || "${REACTIVE_SYSTEM_ADDRESS,,}" != 0x8888888888888888888888888888888888888888 ]]; then
  echo "error: invalid Base Sepolia / Lasna network configuration" >&2
  exit 1
fi

load_deployment() {
  MANIFEST_PATH="${SAFESWEEP_DEPLOYMENT_MANIFEST:-$(ls -1t "$ROOT_DIR"/deployments/base-sepolia-*.json 2>/dev/null | head -1 || true)}"
  if [[ -z "$MANIFEST_PATH" || ! -f "$MANIFEST_PATH" ]]; then
    echo "error: set SAFESWEEP_DEPLOYMENT_MANIFEST to the Base deployment JSON" >&2
    exit 1
  fi
  local values
  values="$(python3 - "$MANIFEST_PATH" <<'PYDATA'
import sys, json, re
d = json.load(open(sys.argv[1]))
if d["origin"]["chain_id"] != 84532 or d["reactive_network"]["chain_id"] != 5318007:
    raise SystemExit("manifest network mismatch")
values = [d[key] for key in ("reactive_contract","vault_contract","guardian","safe_wallet")]
if not all(re.fullmatch(r"0x[0-9a-fA-F]{40}", value) for value in values):
    raise SystemExit("invalid deployment address")
print(*values)
PYDATA
)"
  read -r REACTIVE_ADDRESS VAULT_ADDRESS GUARDIAN_ADDRESS SAFE_WALLET_ADDRESS <<< "$values"
  export REACTIVE_ADDRESS VAULT_ADDRESS GUARDIAN_ADDRESS SAFE_WALLET_ADDRESS
}
