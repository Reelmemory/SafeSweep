"""Read-only receipt proof. Empty getCallbacks bookkeeping is not delivery failure."""
import argparse
from datetime import datetime, timezone
from functools import lru_cache
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
PANIC = "PanicTriggered(address,uint256,bytes32)"
REQUEST = "SweepRequested(bytes32,uint256,address)"
SWEEP = "FundsSwept(address,uint256,bytes32,address)"
CALLBACK = "CallbackRequest(uint256,address,address,uint8,bytes)"
REGISTRY = "getCallbacks(uint256)((uint256,address,uint256,uint256,uint256,bytes)[])"


class ProofError(Exception):
    pass


class RpcError(ProofError):
    pass


def require(condition, message):
    if not condition:
        raise ProofError(message)


def number(value):
    return int(value, 16 if value.startswith("0x") else 10) if isinstance(value, str) else int(value)


def word(value):
    return f"0x{number(value):064x}"


def cast(*args):
    # Offline ABI operations only; never pass authenticated URLs to subprocesses.
    try:
        result = subprocess.run(["cast", *map(str, args)], capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        raise ProofError("Foundry cast is required for offline ABI encoding/decoding") from None
    require(result.returncode == 0, "Offline ABI encoding/decoding failed")
    return result.stdout.strip()


@lru_cache(maxsize=None)
def topic(signature):
    return cast("keccak", signature).lower()


def load_environment():
    # Parse data, never source shell code or load signer credentials. Environment wins.
    path = ROOT / ".env"
    allowed = {"BASE_SEPOLIA_RPC_URL", "LASNA_RPC_URL", "SAFESWEEP_DEPLOYMENT_MANIFEST"}
    if path.exists():
        for line in path.read_text(encoding="utf-8-sig").splitlines():
            key, sep, value = line.strip().partition("=")
            if sep and key in allowed:
                os.environ.setdefault(key, value.strip().strip("\"'"))


class Rpc:
    def __init__(self, url, label):
        self.url, self.label = url, label

    def __call__(self, method, params=None):
        request = urllib.request.Request(self.url, json.dumps({"jsonrpc": "2.0", "id": 1,
            "method": method, "params": params or []}).encode(), {"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=25) as response:
                data = json.load(response)
        except urllib.error.HTTPError as error:
            raise RpcError(f"{self.label} {method}: HTTP {error.code}") from None
        except (OSError, ValueError):
            raise RpcError(f"{self.label} {method}: unavailable or invalid response") from None
        if data.get("error"):
            # Provider error text can contain credentials or request URLs.
            raise RpcError(f"{self.label} {method}: RPC error {data['error'].get('code', 'unknown')}")
        require("result" in data, f"{self.label} {method}: missing result")
        return data["result"]


def call(rpc, address, signature, *args, block="latest"):
    return rpc("eth_call", [{"to": address, "data": cast("calldata", signature, *args)}, block])


def validate_manifest(d):
    require(d["origin"]["chain_id"] == 84532 and d["reactive_network"]["chain_id"] == 5318007,
            "Manifest must target Base Sepolia and Lasna")
    for key in ("vault_contract", "reactive_contract", "guardian", "safe_wallet", "callback_proxy", "reactive_system"):
        require(bool(re.fullmatch(r"0x[0-9a-fA-F]{40}", d.get(key, ""))) and number(d[key]) != 0,
                f"Invalid {key}")
    for key in ("panic_tx", "incident_id"):
        require(bool(re.fullmatch(r"0x[0-9a-fA-F]{64}", d.get(key, ""))), f"Invalid {key}")
    require(d["callback_proxy"].lower() == "0x476f44b11f5c942c58f4c8e3d0300e5710743585",
            "Unexpected Base callback proxy")
    require(d["reactive_system"].lower() == "0x8888888888888888888888888888888888888888",
            "Unexpected Reactive system")


def receipt(rpc, tx):
    require(bool(re.fullmatch(r"0x[0-9a-fA-F]{64}", tx or "")), "Invalid transaction hash")
    result = rpc("eth_getTransactionReceipt", [tx])
    require(result is not None, f"Receipt not yet available: {tx}")
    require(number(result["status"]) == 1 and result["transactionHash"].lower() == tx.lower(),
            f"Failed or mismatched transaction {tx}")
    block = rpc("eth_getBlockByNumber", [result["blockNumber"], False])
    require(block and block["hash"].lower() == result["blockHash"].lower(), "Receipt is not on the canonical chain")
    return result


def event(receipt_data, address, signature, *indexed):
    topics = [topic(signature), *map(word, indexed)]
    matches = []
    for log in receipt_data["logs"]:
        if log["address"].lower() == address.lower() and [t.lower() for t in log["topics"]] == topics:
            require(not log.get("removed", False), "Removed event cannot prove execution")
            require(log["transactionHash"].lower() == receipt_data["transactionHash"].lower()
                    and log["blockHash"].lower() == receipt_data["blockHash"].lower(), "Event receipt mismatch")
            matches.append(log)
    require(len(matches) == 1, f"Expected exactly one matching {signature} event")
    return matches[0]


def uint_data(log):
    require(bool(re.fullmatch(r"0x[0-9a-fA-F]{64}", log["data"])), "Malformed event amount")
    return number(log["data"])


def validate_request(reaction, d):
    event(reaction, d["reactive_contract"], REQUEST, d["incident_id"], d["panic_tx"], d["vault_contract"])
    request = event(reaction, d["reactive_system"], CALLBACK, 84532, d["reactive_contract"], d["vault_contract"])
    # Compare the entire ABI encoding, including dynamic offsets, version and payload.
    payload = "0x8a738683" + "0" * 64 + d["incident_id"][2:].lower()
    config = cast("abi-encode", "f((uint256,address,uint64,bytes))",
                  f"(84532,{d['vault_contract']},350000,{payload})")
    expected = cast("abi-encode", "f(uint8,bytes)", 0, config)
    require(request["data"].lower() == expected.lower(), "Callback request payload/configuration mismatch")
    if "refTx" in reaction:
        require(reaction["refTx"].lower() == d["panic_tx"].lower()
                and number(reaction["refChainId"]) == 84532, "Reactive origin reference mismatch")
    return request


def registry(lasna, d, tx):
    try:
        raw = call(lasna, d["reactive_system"], "getCallbacks(uint256)", tx)
        decoded = json.loads(cast("abi-decode", REGISTRY, raw, "--json"))
        # New Foundry releases wrap offline command output in a result envelope.
        if isinstance(decoded, dict):
            require(decoded.get("success") is True, "Callback registry ABI decode failed")
            decoded = decoded["data"]
        rows = decoded[0]
        return {"status": "available" if rows else "empty", "lookup_tx": tx, "records": rows}
    except RpcError as error:
        return {"status": "unavailable", "lookup_tx": tx, "records": [], "reason": str(error)}


def scan_logs(rpc, address, topics, start, end, chunk=200):
    require(1 <= chunk <= 200, "Log query chunks must be 1–200 blocks")
    cursor = start
    while cursor <= end:
        stop = min(cursor + chunk - 1, end)
        try:
            logs = rpc("eth_getLogs", [{"address": address, "topics": topics,
                "fromBlock": hex(cursor), "toBlock": hex(stop)}])
        except RpcError:
            if chunk == 1:
                raise
            chunk = max(1, chunk // 2)
            continue
        for log in logs:
            require(not log.get("removed", False), "RPC returned a removed log")
            yield log
        cursor = stop + 1


def discover(d, base, lasna, max_blocks=10000):
    origin = receipt(base, d["panic_tx"])
    event(origin, d["vault_contract"], PANIC, d["guardian"], d["incident_id"])
    tx = d.get("reactive_tx")
    if not tx:
        require("lasna_start_block" in d, "No Lasna scan start in manifest")
        start = number(d["lasna_start_block"])
        head = number(lasna("eth_blockNumber"))
        logs = scan_logs(lasna, d["reactive_contract"], [topic(REQUEST), word(d["incident_id"]),
            word(d["panic_tx"]), word(d["vault_contract"])], start, min(head, start + max_blocks - 1))
        first = next(logs, None)
        require(first is not None, "Reactive request not found in bounded scan; delivery status unknown")
        tx = first["transactionHash"]
    reaction = receipt(lasna, tx)
    validate_request(reaction, d)
    d.update(reactive_tx=tx, reactive_block=number(reaction["blockNumber"]))
    if d.get("callback_tx"):
        return tx, d["callback_tx"]
    records = registry(lasna, d, tx)
    d["callback_registry"] = records
    for row in records["records"]:
        if row[1].lower() == d["reactive_contract"].lower() and number(row[3]) == 84532 and number(row[4]) and row[5] == "0x":
            return tx, word(row[4])
    start = number(d.get("base_scan_start_block", origin["blockNumber"]))
    head = number(base("eth_blockNumber"))
    end = min(head, start + max_blocks - 1)
    logs = scan_logs(base, d["vault_contract"], [topic(SWEEP), word(d["safe_wallet"]),
        word(d["incident_id"]), word(d["reactive_contract"])], start, end)
    first = next(logs, None)
    if first:
        return tx, first["transactionHash"]
    d["base_scanned_through"] = end
    failed = any(row[1].lower() == d["reactive_contract"].lower() and number(row[3]) == 84532
                 and row[5] != "0x" for row in records["records"])
    require(False, "Callback attempt failed; no correlated successful delivery found" if failed else
            f"Delivery unconfirmed: no FundsSwept in Base blocks {start}–{end}; registry {records['status']}. "
            "This is not proof of failure. Extend the bounded scan or supply a callback hash.")


def verify(d, base, lasna, reactive_tx, callback_tx):
    validate_manifest(d)
    require(number(base("eth_chainId")) == 84532 and number(lasna("eth_chainId")) == 5318007,
            "RPC chain mismatch")
    vault, reactive = d["vault_contract"], d["reactive_contract"]
    origin, reaction, callback = receipt(base, d["panic_tx"]), receipt(lasna, reactive_tx), receipt(base, callback_tx)
    require(origin["to"].lower() == vault.lower() and origin["from"].lower() == d["guardian"].lower(),
            "Panic transaction caller/target mismatch")
    require(callback["to"].lower() == d["callback_proxy"].lower(), "Destination transaction did not target callback proxy")
    panic = event(origin, vault, PANIC, d["guardian"], d["incident_id"])
    request = validate_request(reaction, d)
    sweep = event(callback, vault, SWEEP, d["safe_wallet"], d["incident_id"], reactive)
    amount = uint_data(sweep)
    require(amount >= uint_data(panic) > 0, "Protected amount is inconsistent")
    block = number(callback["blockNumber"])
    require(block >= number(origin["blockNumber"]), "Callback precedes panic")
    records = registry(lasna, d, reactive_tx)
    matching = [row for row in records["records"] if row[1].lower() == reactive.lower()
                and number(row[3]) == 84532 and number(row[4]) == number(callback_tx)]
    require(all(row[5] == "0x" for row in matching), "Registry contradicts successful destination evidence")
    try:
        generated = lasna("rnk_getCallBackLogs", [number(reaction["blockNumber"])])
        entries = [entry for entry in generated if entry["trx"]["hash"].lower() == reactive_tx.lower()]
        require(any(any(log["data"].lower() == request["data"].lower()
                        and [t.lower() for t in log["topics"]] == [t.lower() for t in request["topics"]]
                        and log["address"].lower() == d["reactive_system"].lower()
                        for log in entry["logs"]) for entry in entries), "Callback generation records mismatch")
        generation = {"status": "confirmed", "entries": entries}
    except RpcError:
        generation = {"status": "unavailable", "receipt_callback_request_verified": True}
    snapshot = base("eth_getBlockByNumber", ["latest", False])
    at = snapshot["number"]
    require(number(at) >= block + 12, "Wait for at least 12 Base confirmations")
    for signature, expected in (("guardian()", d["guardian"]), ("safeWallet()", d["safe_wallet"]),
                                ("_SERVICE_PROVIDER()", d["callback_proxy"]), ("_CALLBACK_SENDER()", reactive)):
        require(number(call(base, vault, signature, block=at)) == number(expected), f"Vault {signature} mismatch")
    swept = number(call(base, vault, "swept()", block=at))
    balance = number(base("eth_getBalance", [vault, at]))
    require(swept == 1 and balance == 0, "Final vault state is not swept=true / balance=0")
    before = number(base("eth_getBalance", [d["safe_wallet"], hex(block - 1)]))
    after = number(base("eth_getBalance", [d["safe_wallet"], hex(block)]))
    require(after - before >= amount, "Beneficiary block balance increase is inconclusive; inspect transfer trace")
    require(base("eth_getBlockByNumber", [at, False])["hash"] == snapshot["hash"], "Snapshot reorg; rerun proof")
    report = dict(schema_version=1, verified_at_utc=datetime.now(timezone.utc).isoformat(),
        origin_receipt=origin, reactive_receipt=reaction, callback_receipt=callback,
        callback_generation=generation, callback_registry=records,
        final_state={"block": number(at), "block_hash": snapshot["hash"], "swept": True,
                     "vault_balance_wei": str(balance), "safe_balance_before_wei": str(before),
                     "safe_balance_after_wei": str(after), "safe_balance_delta_wei": str(after-before)})
    d.update(reactive_tx=reactive_tx, callback_tx=callback_tx, proof_verified=True, proof_status="verified",
        panic_block=number(origin["blockNumber"]), reactive_block=number(reaction["blockNumber"]),
        callback_block=block, swept_wei=str(amount), protected_wei=str(uint_data(panic)), final_vault_balance_wei="0",
        callback_registry=records, verified_at_utc=report["verified_at_utc"], verification_block=number(at))
    return report


def save(path, data):
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    temporary.replace(path)


def main():
    load_environment()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", nargs="?", default=os.environ.get("SAFESWEEP_DEPLOYMENT_MANIFEST"))
    parser.add_argument("reactive_tx", nargs="?")
    parser.add_argument("callback_tx", nargs="?")
    parser.add_argument("--max-blocks", type=int, default=10000)
    args = parser.parse_args()
    if not args.manifest:
        candidates = sorted(p for p in (ROOT / "deployments").glob("base-sepolia-*.json") if not p.stem.endswith("-proof"))
        require(bool(candidates), "No deployment manifest found")
        args.manifest = str(candidates[-1])
    path = Path(args.manifest)
    d = json.loads(path.read_text(encoding="utf-8-sig"))
    d.update(proof_verified=False, proof_status="checking")
    save(path, d)
    try:
        validate_manifest(d)
        require(args.max_blocks > 0, "max-blocks must be positive")
        require(os.environ.get("BASE_SEPOLIA_RPC_URL"), "Set BASE_SEPOLIA_RPC_URL privately in .env or the environment")
        base = Rpc(os.environ["BASE_SEPOLIA_RPC_URL"], "Base")
        lasna = Rpc(os.environ.get("LASNA_RPC_URL", "https://lasna-rpc.rnk.dev/"), "Lasna")
        require(number(base("eth_chainId")) == 84532 and number(lasna("eth_chainId")) == 5318007, "RPC chain mismatch")
        require(bool(args.reactive_tx) == bool(args.callback_tx), "Supply both hashes, or neither")
        txs = (args.reactive_tx, args.callback_tx) if args.reactive_tx else discover(d, base, lasna, args.max_blocks)
        report = verify(d, base, lasna, *txs)
        report_path = path.parent / "evidence" / (path.stem + "-proof.json")
        report_path.parent.mkdir(exist_ok=True)
        save(report_path, report)
        d["proof_report"] = "evidence/" + report_path.name
        d.pop("proof_error", None)
        save(path, d)
        print(f"Verified {d['swept_wei']} wei; callback {d['callback_tx']}; registry {d['callback_registry']['status']}")
    except (ProofError, KeyError, TypeError, ValueError) as error:
        if not isinstance(error, ProofError):
            error = ProofError("Malformed manifest or RPC/ABI response; proof remains unconfirmed")
        d.update(proof_verified=False, proof_status="unconfirmed", proof_error=str(error))
        save(path, d)
        raise error


if __name__ == "__main__":
    try:
        main()
    except ProofError as error:
        print(f"Proof unconfirmed: {error}", file=sys.stderr)
        sys.exit(1)
