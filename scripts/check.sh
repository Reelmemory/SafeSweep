#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/.tools/foundry-nightly"

if ! command -v forge >/dev/null 2>&1 && [[ -x "$TOOLS_DIR/forge" ]]; then
  export PATH="$TOOLS_DIR:$PATH"
fi
if ! command -v forge >/dev/null 2>&1; then
  echo "error: forge is required (https://getfoundry.sh/)" >&2
  exit 127
fi

# Sandbox fallback: use the compiler bundled with the materialized Foundry build
# when outbound solc downloads are unavailable. Normal developer/CI builds keep
# using foundry.toml's Solidity 0.8.29 pin.
if [[ -z "${FOUNDRY_SOLC:-}" && -x "$TOOLS_DIR/solar" ]]; then
  export FOUNDRY_SOLC="$TOOLS_DIR/solar"
fi

forge fmt --check
forge build
forge test -vv
python3 -m unittest discover -s test/evidence -v
node --test test/web/proof.test.mjs
node --check web/app.js
