"""Correlate receipts, callback bookkeeping and the beneficiary balance."""
import json
import os
import subprocess
import sys
from pathlib import Path


def cast(*args):
    return subprocess.check_output(["cast", *map(str, args)], text=True).strip()


def require(condition, message):
    if not condition:
        raise SystemExit(message)


def word(value):
    return f"0x{int(value, 16):064x}"


def receipt(rpc, tx):
    result = json.loads(cast("receipt", tx, "--rpc-url", rpc, "--json"))
    require(int(result["status"], 16) == 1 and result["transactionHash"].lower() == tx.lower(),
            f"Unconfirmed or failed transaction {tx}")
    return result


def event(receipt_data, address, signature, *indexed):
    topics = [cast("keccak", signature), *map(word, indexed)]
    for log in receipt_data["logs"]:
        if log["address"].lower() == address.lower() and log["topics"] == topics:
            return log
    raise SystemExit(f"Missing matching {signature} event")


def main():
    path, reactive_tx, callback_tx = sys.argv[1:]
    manifest = Path(path)
    data = json.loads(manifest.read_text())
    base, lasna = os.environ["BASE_SEPOLIA_RPC_URL"], os.environ["LASNA_RPC_URL"]
    vault, reactive = data["vault_contract"], data["reactive_contract"]
    guardian, safe, incident = data["guardian"], data["safe_wallet"], data["incident_id"]
    panic_tx = data["panic_tx"]
    origin = receipt(base, panic_tx)
    reaction = receipt(lasna, reactive_tx)
    callback = receipt(base, callback_tx)
    panic = event(origin, vault, "PanicTriggered(address,uint256,bytes32)", guardian, incident)
    event(reaction, reactive, "SweepRequested(bytes32,uint256,address)", incident, panic_tx, vault)
    sweep = event(callback, vault, "FundsSwept(address,uint256,bytes32,address)", safe, incident, reactive)
    amount = int(sweep["data"], 16)
    require(amount >= int(panic["data"], 16) > 0, "Protected amount is inconsistent")
    records = json.loads(cast("call", data["reactive_system"],
                        "getCallbacks(uint256)((uint256,address,uint256,uint256,uint256,bytes)[])",
                        reactive_tx, "--rpc-url", lasna, "--json"))[0]
    require(any(row[1].lower() == reactive.lower() and int(row[3]) == 84532
                and int(row[4]) == int(callback_tx, 16) and row[5] == "0x" for row in records),
            "No successful matching callback record")
    block = int(callback["blockNumber"], 16)
    def balance(at):
        return int(cast("balance", safe, "--block", at, "--rpc-url", base))
    require(balance(block) - balance(block - 1) >= amount, "Beneficiary increase unconfirmed")
    require(cast("call", vault, "swept()(bool)", "--rpc-url", base) == "true" and
            cast("balance", vault, "--rpc-url", base) == "0", "Vault evacuation unconfirmed")
    data.update(reactive_tx=reactive_tx, callback_tx=callback_tx, proof_verified=True,
                panic_block=int(origin["blockNumber"], 16), reactive_block=int(reaction["blockNumber"], 16),
                callback_block=block, swept_wei=str(amount))
    temporary = manifest.with_suffix(".tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n")
    temporary.replace(manifest)


if __name__ == "__main__":
    main()
