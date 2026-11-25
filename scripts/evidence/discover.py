"""Compatibility CLI: discover candidates; verify.py still verifies every receipt."""
import json
import os
from pathlib import Path
import sys
from verify import Rpc, ProofError, discover, load_environment, validate_manifest


if __name__ == "__main__":
    try:
        load_environment()
        d = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
        validate_manifest(d)
        print(*discover(d, Rpc(os.environ["BASE_SEPOLIA_RPC_URL"], "Base"), Rpc(sys.argv[2], "Lasna")))
    except (ProofError, KeyError) as error:
        print(f"Discovery unconfirmed: {error}", file=sys.stderr)
        sys.exit(1)
