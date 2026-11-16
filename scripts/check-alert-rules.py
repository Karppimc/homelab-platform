#!/usr/bin/env python3
"""Check and unit-test the platform's alert rules with promtool.

The rules live in PrometheusRule manifests in platform/alerts/, which is what
Argo CD deploys. promtool reads plain rule files, so the script extracts
spec.groups from every manifest into a temporary directory, as
rules/<manifest file name>, copies the test files from tests/alerts/ next to
them and runs:

1. `promtool check rules` on every extracted file,
2. `promtool test rules` on every test file (they refer to rules/<name>.yaml).

It also fails when an alert has no test at all: a rule that is never tested
can be wrong without anyone noticing, because a wrong expression does not
produce an error, the alert just never fires.

Needs promtool and PyYAML. Run from anywhere:

    scripts/check-alert-rules.py
"""

import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
RULES_DIR = REPO_ROOT / "platform/alerts"
TESTS_DIR = REPO_ROOT / "tests/alerts"


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def run(command, cwd):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True, check=False)
    print((result.stdout + result.stderr).strip())
    return result.returncode == 0


def extract_rules(target):
    """Write spec.groups of every PrometheusRule to target/<file name>; return the alert names."""
    alerts = set()
    for path in sorted(RULES_DIR.glob("*.yaml")):
        documents = [doc for doc in yaml.safe_load_all(path.read_text()) if doc]
        if len(documents) != 1 or documents[0].get("kind") != "PrometheusRule":
            fail(f"{path}: expected exactly one PrometheusRule")
        groups = documents[0]["spec"]["groups"]
        for group in groups:
            alerts.update(rule["alert"] for rule in group["rules"] if "alert" in rule)
        (target / path.name).write_text(yaml.safe_dump({"groups": groups}, sort_keys=False))
    if not alerts:
        fail(f"no alert rules found in {RULES_DIR}")
    return alerts


def tested_alerts(test_files):
    """Alert names that at least one test case asserts on."""
    names = set()
    for path in test_files:
        for test in yaml.safe_load(path.read_text()).get("tests") or []:
            names.update(case["alertname"] for case in test.get("alert_rule_test") or [])
    return names


def main():
    if shutil.which("promtool") is None:
        fail("promtool is not on PATH (it ships in the Prometheus release tarball)")
    test_files = sorted(TESTS_DIR.glob("*_test.yaml"))
    if not test_files:
        fail(f"no test files (*_test.yaml) in {TESTS_DIR}")

    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        (work / "rules").mkdir()
        alerts = extract_rules(work / "rules")
        for path in test_files:
            shutil.copy(path, work / path.name)

        untested = sorted(alerts - tested_alerts(test_files))
        if untested:
            fail(f"alerts without a test in {TESTS_DIR}: {', '.join(untested)}")

        print("=== promtool check rules")
        rule_files = sorted(str(p.relative_to(work)) for p in (work / "rules").glob("*.yaml"))
        checked = run(["promtool", "check", "rules", *rule_files], work)
        print("=== promtool test rules")
        tested = run(["promtool", "test", "rules", *[path.name for path in test_files]], work)

    if not (checked and tested):
        fail("the alert rules failed their checks or tests")
    print(f"{len(alerts)} alerts checked, each with at least one test.")


if __name__ == "__main__":
    main()
