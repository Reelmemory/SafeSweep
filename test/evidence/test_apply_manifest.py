import contextlib
import importlib.util
import io
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location("apply_manifest", ROOT / "scripts/web/apply-manifest.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class ApplyManifestTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / "web").mkdir()
        (self.root / "deployments").mkdir()
        self.path = self.root / "deployments/manifest.json"
        self.config = self.root / "web/config.js"
        self.config.write_text("unchanged")
        self.data = json.loads((ROOT / "deployments/base-sepolia-20261124T163546Z.json").read_text())

    def apply(self):
        self.path.write_text(json.dumps(self.data))
        with patch.object(module, "ROOT", self.root), patch.object(module, "CONFIG", self.config), \
             patch("sys.argv", ["apply-manifest.py", str(self.path)]), contextlib.redirect_stdout(io.StringIO()):
            module.main()

    def test_unverified_manifest_does_not_retain_prior_report(self):
        (self.root / "web/proof.json").write_text('{"old":"verified"}')
        self.data["proof_verified"] = False
        self.apply()
        self.assertIn("callbackTx: null", self.config.read_text())
        self.assertFalse(json.loads((self.root / "web/proof.json").read_text())["proof_verified"])

    def test_truthy_string_is_not_verification(self):
        self.data["proof_verified"] = "true"
        self.apply()
        self.assertIn("callbackTx: null", self.config.read_text())
        self.assertIn("verified: false", self.config.read_text())

    def test_report_path_escape_fails_before_writing_config(self):
        self.data["proof_report"] = "../../outside.json"
        with self.assertRaises(SystemExit):
            self.apply()
        self.assertEqual(self.config.read_text(), "unchanged")
