"""Offline regressions. reaction/generation fixtures are unmodified public RPC results."""
import copy
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "evidence"))
import verify as v


class EvidenceTests(unittest.TestCase):
    def setUp(self):
        self.d = json.loads((ROOT / "deployments/base-sepolia-20261124T163546Z.json").read_text())
        self.r = json.loads((Path(__file__).parent / "fixtures/reaction.json").read_text(encoding="utf-8-sig"))

    def test_actual_callback_encoding_and_origin(self):
        v.validate_request(self.r, self.d)

    def test_actual_generation_record_matches_receipt(self):
        entries = json.loads((Path(__file__).parent / "fixtures/callback-generation.json").read_text(encoding="utf-8-sig"))
        entry = next(e for e in entries if e["trx"]["hash"] == self.r["transactionHash"])
        self.assertEqual(entry["logs"][0], self.r["logs"][1])

    def test_wrong_incident_recipient_chain_and_payload_rejected(self):
        for index, field in ((0, 1), (0, 2), (0, 3), (1, 1), (1, 2), (1, 3)):
            with self.subTest(index=index, field=field):
                receipt = copy.deepcopy(self.r)
                receipt["logs"][index]["topics"][field] = v.word(123)
                with self.assertRaises(v.ProofError):
                    v.validate_request(receipt, self.d)
        self.r["logs"][1]["data"] = self.r["logs"][1]["data"][:-2] + "01"
        with self.assertRaises(v.ProofError):
            v.validate_request(self.r, self.d)

    def test_removed_duplicate_and_wrong_receipt_logs_rejected(self):
        for mutation in ("removed", "duplicate", "transaction"):
            with self.subTest(mutation=mutation):
                r = copy.deepcopy(self.r)
                if mutation == "removed":
                    r["logs"][0]["removed"] = True
                elif mutation == "duplicate":
                    r["logs"].append(r["logs"][0])
                else:
                    r["logs"][0]["transactionHash"] = v.word(123)
                with self.assertRaises(v.ProofError):
                    v.validate_request(r, self.d)

    def test_case_insensitive_addresses_and_topics(self):
        for log in self.r["logs"]:
            log["address"] = "0x" + log["address"][2:].upper()
            log["topics"] = ["0x" + t[2:].upper() for t in log["topics"]]
        v.validate_request(self.r, self.d)

    def test_ranges_are_inclusive_at_most_200_blocks(self):
        ranges = []
        def rpc(method, params):
            ranges.append((v.number(params[0]["fromBlock"]), v.number(params[0]["toBlock"])))
            return []
        list(v.scan_logs(rpc, self.d["vault_contract"], [], 10, 410))
        self.assertEqual(ranges, [(10, 209), (210, 409), (410, 410)])

    def test_range_limit_shrinks_without_skipping_blocks(self):
        ranges = []
        def rpc(method, params):
            start, end = v.number(params[0]["fromBlock"]), v.number(params[0]["toBlock"])
            if end - start >= 100:
                raise v.RpcError("HTTP 413")
            ranges.append((start, end))
            return []
        list(v.scan_logs(rpc, self.d["vault_contract"], [], 1, 201))
        self.assertEqual(ranges, [(1, 100), (101, 200), (201, 201)])

    def test_empty_registry_falls_back_to_destination_event(self):
        # Synthetic origin/destination markers isolate discovery; no fabricated public proof.
        origin = {"blockNumber": "0x64"}
        destination = {"transactionHash": "synthetic-callback-candidate"}
        self.d["reactive_tx"] = self.r["transactionHash"]
        self.d["callback_tx"] = None
        with patch.object(v, "receipt", side_effect=[origin, self.r]), patch.object(v, "event"), \
             patch.object(v, "validate_request"), patch.object(v, "registry", return_value={"status": "empty", "records": []}), \
             patch.object(v, "scan_logs", return_value=iter([destination])):
            hashes = v.discover(self.d, lambda *a: "0x100", lambda *a: None)
        self.assertEqual(hashes, (self.r["transactionHash"], "synthetic-callback-candidate"))

    def test_foundry_registry_envelope_and_legacy_array(self):
        for output in ('[[]]', '{"success":true,"data":[[]]}'):
            with patch.object(v, "call", return_value="0x"), patch.object(v, "cast", return_value=output):
                self.assertEqual(v.registry(None, self.d, self.r["transactionHash"])["status"], "empty")

    def test_empty_registry_without_event_is_unconfirmed_not_failed(self):
        self.d["reactive_tx"], self.d["callback_tx"] = self.r["transactionHash"], None
        with patch.object(v, "receipt", side_effect=[{"blockNumber": "0x64"}, self.r]), patch.object(v, "event"), \
             patch.object(v, "validate_request"), patch.object(v, "registry", return_value={"status": "empty", "records": []}), \
             patch.object(v, "scan_logs", return_value=iter([])):
            with self.assertRaisesRegex(v.ProofError, "Delivery unconfirmed"):
                v.discover(self.d, lambda *a: "0x100", lambda *a: None)

    def test_receipt_failure_and_reorg_rejected(self):
        for status, block_hash in (("0x0", self.r["blockHash"]), ("0x1", v.word(123))):
            r = dict(self.r, status=status)
            def rpc(method, params):
                return r if method == "eth_getTransactionReceipt" else {"hash": block_hash}
            with self.assertRaises(v.ProofError):
                v.receipt(rpc, self.r["transactionHash"])

    def test_rpc_errors_do_not_expose_url_or_provider_messages(self):
        response = unittest.mock.MagicMock()
        response.__enter__.return_value.read.return_value = b'{"error":{"code":-1,"message":"secret-key"}}'
        with patch("urllib.request.urlopen", return_value=response):
            with self.assertRaises(v.RpcError) as error:
                v.Rpc("https://example.invalid/secret-key", "Base")("eth_chainId")
        self.assertNotIn("secret-key", str(error.exception))


class PublicProofReplay(unittest.TestCase):
    """Replay actual chain evidence offline, then corrupt each trust boundary."""
    def setUp(self):
        self.d = json.loads((ROOT / "deployments/base-sepolia-20261124T163546Z.json").read_text())
        self.p = json.loads((ROOT / "deployments/evidence/base-sepolia-20261124T163546Z-proof.json").read_text())
        self.getters = {v.cast("calldata", signature): v.word(value) for signature, value in [
            ("guardian()", self.d["guardian"]), ("safeWallet()", self.d["safe_wallet"]),
            ("_SERVICE_PROVIDER()", self.d["callback_proxy"]), ("_CALLBACK_SENDER()", self.d["reactive_contract"]),
            ("swept()", 1)]}

    def rpc(self, chain, method, params=None):
        params = params or []
        receipts = [self.p["reactive_receipt"]] if chain == "lasna" else [self.p["origin_receipt"], self.p["callback_receipt"]]
        final = self.p["final_state"]
        if method == "eth_chainId":
            return hex(5318007 if chain == "lasna" else 84532)
        if method == "eth_getTransactionReceipt":
            return next(r for r in receipts if r["transactionHash"] == params[0])
        if method == "eth_getBlockByNumber":
            if params[0] in ("latest", hex(final["block"])):
                return {"number": hex(final["block"]), "hash": final["block_hash"]}
            return {"hash": next(r["blockHash"] for r in receipts if r["blockNumber"] == params[0])}
        if method == "eth_call":
            if chain == "lasna":
                return v.word(32) + v.word(0)[2:]
            return self.getters[params[0]["data"]]
        if method == "rnk_getCallBackLogs":
            return self.p["callback_generation"]["entries"]
        if method == "eth_getBalance":
            if params[0] == self.d["vault_contract"]:
                return hex(int(final["vault_balance_wei"]))
            key = "safe_balance_after_wei" if params[1] == self.p["callback_receipt"]["blockNumber"] else "safe_balance_before_wei"
            return hex(int(final[key]))
        raise AssertionError(method)

    def verify(self):
        return v.verify(self.d, lambda *args: self.rpc("base", *args), lambda *args: self.rpc("lasna", *args),
                        self.d["reactive_tx"], self.d["callback_tx"])

    def test_complete_public_proof_passes_with_empty_registry(self):
        report = self.verify()
        self.assertTrue(self.d["proof_verified"])
        self.assertEqual(report["callback_registry"]["status"], "empty")
        self.assertEqual(report["final_state"]["safe_balance_delta_wei"], "5000000000000000")

    def test_state_alone_never_proves_callback(self):
        self.p["callback_receipt"]["logs"] = []
        with self.assertRaises(v.ProofError):
            self.verify()

    def test_wrong_safe_wallet_rejected(self):
        self.d["safe_wallet"] = "0x" + "12" * 20
        with self.assertRaises(v.ProofError):
            self.verify()

    def test_beneficiary_did_not_gain_funds_rejected(self):
        self.p["final_state"]["safe_balance_after_wei"] = "0"
        with self.assertRaisesRegex(v.ProofError, "Beneficiary"):
            self.verify()

    def test_nonzero_retired_vault_balance_rejected(self):
        self.p["final_state"]["vault_balance_wei"] = "1"
        with self.assertRaisesRegex(v.ProofError, "Final vault state"):
            self.verify()

    def test_wrong_callback_proxy_rejected(self):
        self.p["callback_receipt"]["to"] = self.d["guardian"]
        with self.assertRaisesRegex(v.ProofError, "proxy"):
            self.verify()


if __name__ == "__main__":
    unittest.main()
