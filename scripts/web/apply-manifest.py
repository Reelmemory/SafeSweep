#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CONFIG = ROOT / "web" / "config.js"


def die(message: str) -> None:
    raise SystemExit(f"error: {message}")


def evm_address(value, field):
    if not isinstance(value, str) or not re.fullmatch(r"0x[0-9a-fA-F]{40}", value):
        die(f"{field} is not a valid EVM address")
    return value


def tx_hash(value, field):
    if value is None:
        return None
    if not isinstance(value, str) or not re.fullmatch(r"0x[0-9a-fA-F]{64}", value):
        die(f"{field} is not a valid transaction hash")
    return value


def q(value):
    return json.dumps(value)


def main() -> None:
    if len(sys.argv) != 2:
        die("usage: apply-manifest.py deployments/base-sepolia-<timestamp>.json")

    manifest_path = Path(sys.argv[1]).expanduser().resolve()
    if not manifest_path.is_file():
        die(f"manifest not found: {manifest_path}")

    data = json.loads(manifest_path.read_text())
    if data.get("project") != "SafeSweep":
        die("manifest project is not SafeSweep")

    origin = data.get("origin") or {}
    reactive_network = data.get("reactive_network") or {}
    origin_chain_id = int(origin.get("chain_id", 0))
    reactive_chain_id = int(reactive_network.get("chain_id", 0))
    if origin_chain_id != 84532:
        die(f"unsupported origin chain id {origin_chain_id}; expected Base Sepolia 84532")
    if reactive_chain_id != 5318007:
        die(f"unsupported Reactive chain id {reactive_chain_id}; expected Lasna 5318007")

    vault = evm_address(data.get("vault_contract"), "vault_contract")
    reactive = evm_address(data.get("reactive_contract"), "reactive_contract")
    callback_proxy = evm_address(data.get("callback_proxy"), "callback_proxy")
    system = evm_address(data.get("reactive_system"), "reactive_system")
    guardian = evm_address(data.get("guardian"), "guardian")
    safe_wallet = evm_address(data.get("safe_wallet"), "safe_wallet")

    panic_tx = tx_hash(data.get("panic_tx"), "panic_tx")
    reactive_tx = tx_hash(data.get("reactive_tx"), "reactive_tx")
    callback_tx = tx_hash(data.get("callback_tx"), "callback_tx")

    if data.get("proof_verified") is not True:
        reactive_tx = callback_tx = None

    incident = tx_hash(data.get("incident_id"), "incident_id")
    amount = data.get("swept_wei")
    if amount is not None and not re.fullmatch(r"[0-9]+", str(amount)):
        die("swept_wei is invalid")

    content = f'''export const config = {{
  appName: "SafeSweep",
  demoMode: false,
  origin: {{
    name: "Base Sepolia",
    chainId: {origin_chain_id},
    chainIdHex: "0x{origin_chain_id:x}",
    explorer: "https://sepolia.basescan.org",
  }},
  reactive: {{
    name: "Reactive Lasna",
    chainId: {reactive_chain_id},
    explorer: "https://lasna.reactscan.net",
  }},
  addresses: {{
    vault: {q(vault)},
    reactive: {q(reactive)},
    callbackProxy: {q(callback_proxy)},
    system: {q(system)},
  }},
  proof: {{
    panicTx: {q(panic_tx)},
    reactiveTx: {q(reactive_tx)},
    callbackTx: {q(callback_tx)},
    incidentId: {q(incident)},
    amountWei: {q(amount)},
    verified: {q(data.get("proof_verified") is True)},
  }},
  demo: {{
    balanceEth: "0.0000",
    vault: {q(vault)},
    reactive: {q(reactive)},
    guardian: {q(guardian)},
    safeWallet: {q(safe_wallet)},
  }},
}};
'''
    report = data.get("proof_report")
    report_content = json.dumps({"proof_verified": False, "status": "No verified report for this deployment"}, indent=2) + "\n"
    if data.get("proof_verified") is True and report:
        source = (manifest_path.parent / report).resolve()
        if not source.is_relative_to(manifest_path.parent):
            die("proof_report must be inside deployments")
        report_content = source.read_text(encoding="utf-8")
        json.loads(report_content)
    # Validate everything before replacing generated artifacts. Never retain a prior
    # deployment's report when applying an unverified/new manifest.
    (ROOT / "web" / "proof.json").write_text(report_content, encoding="utf-8")
    CONFIG.write_text(content, encoding="utf-8")
    print(f"updated {CONFIG.relative_to(ROOT)} from {manifest_path}")
    if not all((panic_tx, reactive_tx, callback_tx)):
        print("note: deployment addresses are live, but proof hashes are not all recorded yet")


if __name__ == "__main__":
    main()
