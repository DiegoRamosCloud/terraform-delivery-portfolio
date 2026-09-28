import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location("delivery", Path(__file__).parents[1] / "aws_delivery.py")
delivery = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(delivery)


class DeliveryTests(unittest.TestCase):
    def setUp(self):
        self.ctx = {"GITHUB_SHA": "a" * 40, "GITHUB_RUN_ID": "123", "GITHUB_RUN_ATTEMPT": "1",
                    "AWS_REGION": "us-east-1", "TFSTATE_BUCKET": "test-bucket", "object_key": "plans/hml/123/1/plan.zip"}
        self.manifest = {"commit": "a" * 40, "run_id": "123", "attempt": "1", "lock_hash": "hash",
                         "terraform_version": "1.14.7", "stack": "aws-hml", "created_at": 1000}

    def test_matching_manifest_accepted(self):
        delivery.validate_manifest(self.manifest, self.ctx, "hash", 1100)

    def test_wrong_provenance_rejected(self):
        for field in ["commit", "run_id", "attempt", "lock_hash", "stack", "terraform_version"]:
            with self.subTest(field=field), self.assertRaises(delivery.DeliveryError):
                delivery.validate_manifest(dict(self.manifest, **{field: "wrong"}), self.ctx, "hash", 1100)

    def test_expired_or_future_plan_rejected(self):
        for created in [-10000, 1200, None, "1000"]:
            with self.subTest(created=created), self.assertRaises(delivery.DeliveryError):
                delivery.validate_manifest(dict(self.manifest, created_at=created), self.ctx, "hash", 1100)

    def test_command_error_does_not_expose_raw_output(self):
        result = subprocess.CompletedProcess(["terraform"], 1, "secret-canary", "AccessDenied private-bucket")
        with patch.object(delivery.subprocess, "run", return_value=result):
            with self.assertRaises(delivery.DeliveryError) as error:
                delivery.command(["terraform", "plan"])
        self.assertIn("AccessDenied", str(error.exception))
        self.assertNotIn("secret-canary", str(error.exception))
        self.assertNotIn("private-bucket", str(error.exception))

    def test_policy_denial_blocks_plan(self):
        result = subprocess.CompletedProcess([], 0, json.dumps({"result": [{"expressions": [{"value": ["delete denied"]}]}]}))
        with patch.object(delivery, "command", return_value=result), self.assertRaises(delivery.DeliveryError):
            delivery.evaluate(Path("plan.json"))

    def test_undefined_policy_is_not_allowed(self):
        result = subprocess.CompletedProcess([], 0, '{"result": []}')
        with patch.object(delivery, "command", return_value=result), self.assertRaises(IndexError):
            delivery.evaluate(Path("plan.json"))

    def test_summary_omits_values_and_resource_names(self):
        with tempfile.TemporaryDirectory() as tmp:
            output = Path(tmp) / "summary"
            with patch.dict(os.environ, {"GITHUB_STEP_SUMMARY": str(output), "GITHUB_SHA": "a" * 40}):
                delivery.summary({"resource_changes": [{"address": "private-name", "change": {
                    "actions": ["create"], "after": {"value": "secret-canary"}}}]}, "Plan")
            text = output.read_text()
            self.assertIn("Create: 1", text)
            self.assertNotIn("secret-canary", text)
            self.assertNotIn("private-name", text)

    def test_altered_plan_stops_before_terraform(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            (folder / "plan.zip").write_bytes(b"tampered")
            with patch.dict(os.environ, {"EXPECTED_PLAN_SHA256": "b" * 64}), \
                    patch.object(delivery, "command") as command, \
                    patch.object(delivery, "initialize") as initialize:
                with self.assertRaisesRegex(delivery.DeliveryError, "integrity"):
                    delivery.apply(self.ctx, folder)
                initialize.assert_not_called()
                self.assertEqual(command.call_count, 1)
                self.assertEqual(command.call_args.args[0][0], "aws")

    def test_unexpected_plan_action_fails_closed(self):
        with self.assertRaises(delivery.DeliveryError):
            delivery.summary({"resource_changes": [{"change": {"actions": ["new-action"]}}]}, "Plan")

    def test_private_plan_round_trip(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / ".terraform.lock.hcl").write_text("test lock")
            output = root / "outputs"
            summary = root / "summary"
            stored = {}

            def tool(args, accepted=(0,)):
                if args[:2] == ["terraform", "plan"]:
                    plan_path = next(arg.removeprefix("-out=") for arg in args if arg.startswith("-out="))
                    Path(plan_path).write_bytes(b"approved binary plan")
                    return subprocess.CompletedProcess(args, 2, "private value - must not be published", "")
                if args[:2] == ["terraform", "show"]:
                    payload = {"terraform_version": "1.14.7", "resource_changes": [
                        {"change": {"actions": ["create"], "after": {"value": "secret-canary"}}}]}
                    return subprocess.CompletedProcess(args, 0, json.dumps(payload), "")
                if args[0] == "opa":
                    return subprocess.CompletedProcess(args, 0, '{"result":[{"expressions":[{"value":[]}]}]}', "")
                if args[:3] == ["aws", "s3", "cp"]:
                    if args[3].startswith("s3://"):
                        Path(args[4]).write_bytes(stored["archive"])
                    else:
                        self.assertIn("AES256", args)
                        stored["archive"] = Path(args[3]).read_bytes()
                if args[:2] == ["terraform", "apply"]:
                    self.assertEqual(Path(args[-1]).read_bytes(), b"approved binary plan")
                    stored["applied"] = True
                return subprocess.CompletedProcess(args, 0, "", "")

            with patch.object(delivery, "STACK", root), patch.object(delivery, "command", side_effect=tool), \
                    patch.dict(os.environ, {"GITHUB_SHA": "a" * 40, "GITHUB_STEP_SUMMARY": str(summary),
                                            "GITHUB_OUTPUT": str(output)}):
                delivery.plan(self.ctx, root)
                expected_hash = output.read_text().strip().split("=", 1)[1]
                with patch.dict(os.environ, {"EXPECTED_PLAN_SHA256": expected_hash}):
                    delivery.apply(self.ctx, root)
            self.assertTrue(stored["applied"])
            self.assertNotIn("secret-canary", summary.read_text())
            self.assertNotIn("private value", summary.read_text())


if __name__ == "__main__":
    unittest.main()
