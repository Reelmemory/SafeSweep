#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/.tools/foundry-nightly"

if ! command -v forge >/dev/null 2>&1 && [[ -x "$TOOLS_DIR/forge" ]]; then
  export PATH="$TOOLS_DIR:$PATH"
fi
if [[ -z "${FOUNDRY_SOLC:-}" && -x "$TOOLS_DIR/solar" ]]; then
  export FOUNDRY_SOLC="$TOOLS_DIR/solar"
fi
export FOUNDRY_DISABLE_NIGHTLY_WARNING=1

load_env_for_wrapper() {
  if [[ -f "$ROOT_DIR/.env" ]]; then
    set -a
    # shellcheck disable=SC1091
    source "$ROOT_DIR/.env"
    set +a
  fi
}

with_keystore_session() {
  load_env_for_wrapper
  if [[ -n "${PRIVATE_KEY:-}" || -z "${SAFESWEEP_ACCOUNT:-}" || -n "${SAFESWEEP_PASSWORD_FILE:-}" ]]; then
    "$@"
    return
  fi

  if [[ ! -t 0 ]]; then
    echo "error: keystore password prompt requires an interactive terminal" >&2
    exit 1
  fi

  local pw tmp
  read -r -s -p "Foundry keystore password for ${SAFESWEEP_ACCOUNT}: " pw
  echo
  tmp="$(mktemp)"
  chmod 600 "$tmp"
  printf '%s' "$pw" > "$tmp"
  unset pw
  export SAFESWEEP_PASSWORD_FILE="$tmp"
  trap 'rm -f "$SAFESWEEP_PASSWORD_FILE"' EXIT INT TERM
  "$@"
}

latest_manifest() {
  ls -1t "$ROOT_DIR"/deployments/base-sepolia-*.json 2>/dev/null | head -1 || true
}

usage() {
  cat <<'TXT'
SafeSweep operator CLI

Usage:
  ./scripts/safesweep.sh init
  ./scripts/safesweep.sh wallet-import
  ./scripts/safesweep.sh check
  ./scripts/safesweep.sh rehearse
  ./scripts/safesweep.sh preflight
  ./scripts/safesweep.sh request-lreact
  ./scripts/safesweep.sh deploy
  ./scripts/safesweep.sh status
  ./scripts/safesweep.sh panic
  ./scripts/safesweep.sh proof <reactive-tx-hash> <callback-tx-hash>
  ./scripts/safesweep.sh apply-ui [manifest.json]
  ./scripts/safesweep.sh serve-ui [port]

Recommended live sequence:
  init -> wallet-import -> preflight -> request-lreact (if needed) -> deploy -> panic -> proof -> apply-ui

The recommended live signer is an encrypted Foundry keystore account. Do not paste a production private key into chat or commit it to the repo.
TXT
}

cmd="${1:-help}"
shift || true
cd "$ROOT_DIR"

case "$cmd" in
  init)
    if [[ -f .env ]]; then
      echo ".env already exists; leaving it unchanged"
    else
      cp .env.example .env
      chmod 600 .env
      echo "created .env from .env.example"
    fi
    echo "Next: set BASE_SEPOLIA_RPC_URL, GUARDIAN_ADDRESS, and SAFE_WALLET_ADDRESS in .env."
    echo "Recommended signer: SAFESWEEP_ACCOUNT=safesweep-testnet"
    ;;
  wallet-import)
    command -v cast >/dev/null 2>&1 || { echo "error: cast is required" >&2; exit 1; }
    load_env_for_wrapper
    account="${SAFESWEEP_ACCOUNT:-safesweep-testnet}"
    echo "Importing a dedicated TESTNET key into Foundry's encrypted keystore as '$account'."
    echo "The key is entered in your terminal's hidden prompt and is not written to .env."
    cast wallet import "$account" --interactive
    ;;
  check)
    ./scripts/check.sh
    ;;
  rehearse)
    ./scripts/local/rehearse.sh
    ;;
  preflight)
    with_keystore_session ./scripts/deploy/00-preflight.sh
    ;;
  request-lreact)
    with_keystore_session ./scripts/deploy/00-request-lreact.sh
    ;;
  deploy)
    with_keystore_session ./scripts/deploy/ship-live.sh
    ;;
  status)
    source ./scripts/deploy/common.sh
    load_deployment
    export SAFESWEEP_SKIP_DOTENV=1
    ./scripts/deploy/06-status.sh
    ;;
  panic)
    with_keystore_session ./scripts/deploy/07-panic.sh
    ;;
  proof)
    if [[ $# -ne 0 && $# -ne 2 ]]; then
      echo "usage: $0 proof <reactive-tx-hash> <callback-tx-hash>" >&2
      exit 1
    fi
    python3 scripts/evidence/verify.py "${SAFESWEEP_DEPLOYMENT_MANIFEST:-$(latest_manifest)}" "$@"
    ;;
  apply-ui)
    manifest="${1:-$(latest_manifest)}"
    if [[ -z "$manifest" || ! -f "$manifest" ]]; then
      echo "error: no live deployment manifest found" >&2
      exit 1
    fi
    ./scripts/web/apply-manifest.py "$manifest"
    echo "dashboard configured from $manifest"
    ;;
  serve-ui)
    port="${1:-4173}"
    exec python3 -m http.server "$port" -d web
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "error: unknown command '$cmd'" >&2
    usage >&2
    exit 1
    ;;
esac
