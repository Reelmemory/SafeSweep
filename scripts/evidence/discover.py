"""Find the Lasna request for this recorded panic and its delivered Base callback."""
import json
import sys
from pathlib import Path
from verify import cast, require, word


def main():
    manifest, rpc = sys.argv[1:]
    d = json.loads(Path(manifest).read_text())
    require(d.get("panic_tx") and "lasna_start_block" in d, "No recorded panic with a Lasna start block")
    start = d["lasna_start_block"]
    head = int(cast("block-number", "--rpc-url", rpc))
    for block in range(start, head + 1, 500):
        query = dict(address=d["reactive_contract"], fromBlock=hex(block), toBlock=hex(min(block+499,head)),
                     topics=[cast("keccak","SweepRequested(bytes32,uint256,address)"), d["incident_id"],
                             d["panic_tx"], word(d["vault_contract"])])
        logs = json.loads(cast("rpc","eth_getLogs",json.dumps(query),"--rpc-url",rpc))
        if not logs:
            continue
        tx = logs[0]["transactionHash"]
        records = json.loads(cast("call",d["reactive_system"],
            "getCallbacks(uint256)((uint256,address,uint256,uint256,uint256,bytes)[])",tx,
            "--rpc-url",rpc,"--json"))[0]
        for row in records:
            if row[1].lower() == d["reactive_contract"].lower() and int(row[3]) == 84532 and int(row[4]) and row[5] == "0x":
                print(tx, f"0x{int(row[4]):064x}")
                return
        raise SystemExit(f"Lasna request {tx} found. Base delivery is pending or failed. Run proof again after delivery.")
    raise SystemExit("Lasna request not found in the scanned blocks. Run proof again, or supply verified transaction hashes.")


if __name__ == "__main__":
    main()
