#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT_DIR"
manifest="${SAFESWEEP_DEPLOYMENT_MANIFEST:-$(ls -1 deployments/base-sepolia-*.json | sort | tail -1)}"
exec python3 scripts/evidence/verify.py "$manifest" "$@"
