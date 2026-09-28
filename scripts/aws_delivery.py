#!/usr/bin/env python3
"""Private plan exchange for one hml stack; never print Terraform/AWS raw output."""

import argparse
from collections import Counter
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
STACK = ROOT / "stacks/aws-hml"
MAX_PLAN_AGE = 3600


class DeliveryError(Exception):
    pass


def command(args, accepted=(0,)):
    result = subprocess.run(args, cwd=STACK, text=True, capture_output=True, timeout=720)
    if result.returncode not in accepted:
        text = result.stdout + result.stderr
        category = "tool_error"
        for keyword in ("AccessDenied", "Access Denied", "Saved plan is stale",
                        "Error acquiring the state lock", "Invalid value", "NoSuchBucket"):
            if keyword.lower() in text.lower():
                category = keyword
                break
        raise DeliveryError(f"{args[0]} {args[1]} failed ({category}); raw output withheld in public CI. See the runbook.")
    return result


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def context():
    patterns = {
        "TFSTATE_BUCKET": r"[a-z0-9][a-z0-9-]{1,61}[a-z0-9]",
        "AWS_REGION": r"[a-z]{2}-[a-z]+-[0-9]+",
        "TF_VAR_aws_account_id": r"[0-9]{12}",
        "GITHUB_SHA": r"[0-9a-f]{40}",
        "GITHUB_RUN_ID": r"[0-9]+",
        "GITHUB_RUN_ATTEMPT": r"[0-9]+",
    }
    values = {}
    for name, pattern in patterns.items():
        value = os.environ.get(name, "")
        if not re.fullmatch(pattern, value):
            raise DeliveryError(f"Missing or invalid configuration: {name}")
        values[name] = value
    values["object_key"] = f"plans/hml/{values['GITHUB_RUN_ID']}/{values['GITHUB_RUN_ATTEMPT']}/plan.zip"
    return values


def initialize(ctx):
    command(["terraform", "init", "-input=false", "-no-color", "-lockfile=readonly",
             f"-backend-config=bucket={ctx['TFSTATE_BUCKET']}",
             f"-backend-config=region={ctx['AWS_REGION']}"])


def summary(plan, heading):
    counts = Counter()
    allowed = {"no-op", "read", "create", "update", "delete", "forget"}
    for change in plan.get("resource_changes", []):
        actions = change["change"]["actions"]
        if not actions or not set(actions) <= allowed:
            raise DeliveryError("Unknown plan action: review the parser before proceeding.")
        counts.update(actions)
    message = (f"### {heading}\n\nCommit: `{os.environ['GITHUB_SHA']}`\n\n"
               f"Create: {counts['create']} | Update: {counts['update']} | "
               f"Delete: {counts['delete']} | Forget: {counts['forget']} | "
               f"No-op: {counts['no-op']}\n\n"
               "Values and raw plans are intentionally omitted from public logs.\n")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as output:
        output.write(message)
    return counts


def evaluate(plan_path):
    result = command(["opa", "eval", "--format=json", "--data", str(ROOT / "policies/opa"),
                      "--input", str(plan_path), "data.terraform.guard.deny"])
    denies = json.loads(result.stdout)["result"][0]["expressions"][0]["value"]
    if not isinstance(denies, list):
        raise DeliveryError("Invalid policy result; refusing deployment.")
    if denies:
        raise DeliveryError(f"OPA denied the plan ({len(denies)} findings). Review destructive actions or S3 protections locally.")


def validate_manifest(manifest, ctx, lock_hash, now):
    expected = {
        "commit": ctx["GITHUB_SHA"],
        "run_id": ctx["GITHUB_RUN_ID"],
        "attempt": ctx["GITHUB_RUN_ATTEMPT"],
        "lock_hash": lock_hash,
        "terraform_version": "1.14.7",
        "stack": "aws-hml",
    }
    if any(manifest.get(key) != value for key, value in expected.items()):
        raise DeliveryError("Plan provenance mismatch: commit, run, attempt, stack, version or lockfile.")
    created = manifest.get("created_at")
    if not isinstance(created, (int, float)) or not 0 <= now - created <= MAX_PLAN_AGE:
        raise DeliveryError("Plan expired or timestamp invalid. Re-run all jobs and approve a new plan.")


def plan(ctx, folder, drift=False):
    binary = folder / "tfplan"
    result = command(["terraform", "plan", "-input=false", "-no-color", "-lock-timeout=60s",
                      "-detailed-exitcode", f"-out={binary}"], accepted=(0, 2))
    # JSON is sensitive, even when Terraform marks individual values as sensitive.
    payload = command(["terraform", "show", "-json", str(binary)]).stdout
    parsed = json.loads(payload)
    plan_json = folder / "plan.json"
    plan_json.write_text(payload, encoding="utf-8")
    summary(parsed, "Drift check" if drift else "AWS hml deployment plan")
    if drift:
        if result.returncode == 2:
            raise DeliveryError("Drift/difference detected (Terraform exit 2). Investigate; no automatic apply performed.")
        print("Drift check clean (Terraform exit 0).")
        return
    evaluate(plan_json)
    if any("forget" in change["change"]["actions"] for change in parsed.get("resource_changes", [])):
        raise DeliveryError("State removal is outside this lab's deployment contract.")
    manifest = {
        "commit": ctx["GITHUB_SHA"], "run_id": ctx["GITHUB_RUN_ID"],
        "attempt": ctx["GITHUB_RUN_ATTEMPT"], "created_at": time.time(),
        "lock_hash": digest(STACK / ".terraform.lock.hcl"),
        "terraform_version": parsed["terraform_version"], "stack": "aws-hml",
    }
    archive = folder / "plan.zip"
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        bundle.write(binary, "tfplan")
        bundle.writestr("manifest.json", json.dumps(manifest))
    command(["aws", "s3", "cp", str(archive),
             f"s3://{ctx['TFSTATE_BUCKET']}/{ctx['object_key']}", "--sse", "AES256", "--only-show-errors"])
    with open(os.environ["GITHUB_OUTPUT"], "a", encoding="utf-8") as output:
        output.write(f"plan_sha256={digest(archive)}\n")
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as output:
        output.write(f"\nPrivate plan SHA-256: `{digest(archive)}`\n\nMaximum plan age: 60 minutes.\n")
    print("Plan passed OPA and was stored privately in S3. Approval is valid for at most 60 minutes from plan creation.")


def apply(ctx, folder):
    expected = os.environ.get("EXPECTED_PLAN_SHA256", "")
    if not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise DeliveryError("Missing plan digest from the plan job.")
    archive = folder / "plan.zip"
    command(["aws", "s3", "cp", f"s3://{ctx['TFSTATE_BUCKET']}/{ctx['object_key']}",
             str(archive), "--only-show-errors"])
    if digest(archive) != expected:
        raise DeliveryError("Private plan integrity check failed.")
    with zipfile.ZipFile(archive) as bundle:
        manifest = json.loads(bundle.read("manifest.json"))
        validate_manifest(manifest, ctx, digest(STACK / ".terraform.lock.hcl"), time.time())
        binary = folder / "tfplan"
        binary.write_bytes(bundle.read("tfplan"))
    initialize(ctx)
    validate_manifest(manifest, ctx, digest(STACK / ".terraform.lock.hcl"), time.time())
    command(["terraform", "apply", "-input=false", "-no-color", "-lock-timeout=60s", str(binary)])
    with open(os.environ["GITHUB_STEP_SUMMARY"], "a", encoding="utf-8") as output:
        output.write("### AWS hml apply\n\nApproved saved plan applied successfully. State is persisted in S3.\n")
    print("Approved saved plan applied successfully.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["plan", "apply", "drift"])
    args = parser.parse_args()
    ctx = context()
    with tempfile.TemporaryDirectory(prefix="private-tf-plan-") as folder:
        if args.mode == "apply":
            apply(ctx, Path(folder))
        else:
            initialize(ctx)
            plan(ctx, Path(folder), drift=args.mode == "drift")


if __name__ == "__main__":
    try:
        main()
    except DeliveryError as error:
        print(f"::error::{error}", file=sys.stderr)
        sys.exit(1)
    except (OSError, ValueError, KeyError, IndexError, TypeError, zipfile.BadZipFile, subprocess.TimeoutExpired):
        print("::error::Invalid configuration, tool output, archive or timeout. No raw data published; see the runbook.", file=sys.stderr)
        sys.exit(1)
