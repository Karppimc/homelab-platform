#!/usr/bin/env python3
"""Check the Alertmanager configuration and the Discord message templates.

The configuration and the templates live in the kube-prometheus-stack values
(alertmanager.config and alertmanager.templateFiles). The script writes them
out as Alertmanager would see them and runs:

1. `amtool check-config`, with a placeholder for the webhook URL file,
2. `amtool template render` of the Discord receiver's title and message for
   every case in tests/alertmanager/*.json (Alertmanager's notification data),
   compared with <case>.title.txt and <case>.message.txt next to it.

A broken template does not fail at deploy time: Alertmanager fails to send the
notification, so the alert never arrives. This is the only place that shows it.
It also checks Discord's limits: a title of at most 256 and a message of at
most 4096 characters.

Needs amtool and PyYAML. To rewrite the expected files after an intended change:

    scripts/check-alertmanager.py --update
"""

import argparse
import difflib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
VALUES = REPO_ROOT / "platform/monitoring/kube-prometheus-stack-values.yaml"
CASES = REPO_ROOT / "tests/alertmanager"
LIMITS = {"title": 256, "message": 4096}


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def render(amtool, templates, data, text):
    result = subprocess.run(
        [amtool, "template", "render", f"--template.glob={templates}",
         f"--template.data={data}", f"--template.text={text}"],
        capture_output=True, text=True, check=False)
    if result.returncode != 0:
        fail(f"rendering {data.name} failed:\n{result.stderr}")
    return result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--update", action="store_true", help="rewrite the expected output files")
    args = parser.parse_args()

    amtool = shutil.which("amtool")
    if amtool is None:
        fail("amtool is not on PATH (it ships in the Alertmanager release tarball)")
    alertmanager = yaml.safe_load(VALUES.read_text())["alertmanager"]
    config, template_files = alertmanager["config"], alertmanager.get("templateFiles") or {}
    discord = [c for r in config["receivers"] for c in r.get("discord_configs") or []]
    if len(discord) != 1:
        fail(f"expected exactly one discord_configs entry, found {len(discord)}")
    discord = discord[0]

    cases = sorted(CASES.glob("*.json"))
    if not cases:
        fail(f"no test cases (*.json) in {CASES}")

    with tempfile.TemporaryDirectory() as tmp:
        work = Path(tmp)
        for name, content in template_files.items():
            (work / name).write_text(content)
        templates = str(work / "*.tmpl")
        # The real webhook URL is a secret in the cluster; amtool only needs a file
        url_file = work / "webhook-url"
        url_file.write_text("https://discord.com/api/webhooks/0/placeholder\n")
        discord["webhook_url_file"] = str(url_file)
        config["templates"] = [templates]
        (work / "alertmanager.yaml").write_text(yaml.safe_dump(config))

        print("=== amtool check-config")
        check = subprocess.run([amtool, "check-config", str(work / "alertmanager.yaml")],
                               capture_output=True, text=True, check=False)
        print((check.stdout + check.stderr).strip())
        if check.returncode != 0:
            fail("amtool check-config failed")

        print("=== Discord messages")
        failed = False
        for case in cases:
            for part in ("title", "message"):
                got = render(amtool, templates, case, discord[part])
                if len(got) > LIMITS[part]:
                    print(f"{case.stem} {part}: {len(got)} characters, Discord allows {LIMITS[part]}")
                    failed = True
                expected_file = case.with_suffix(f".{part}.txt")
                if args.update:
                    expected_file.write_text(got)
                    continue
                expected = expected_file.read_text() if expected_file.exists() else None
                if got != expected:
                    failed = True
                    print(f"{case.stem} {part}: differs from {expected_file.name}")
                    sys.stdout.writelines(difflib.unified_diff(
                        (expected or "").splitlines(keepends=True), got.splitlines(keepends=True),
                        "expected", "rendered"))
                else:
                    print(f"{case.stem} {part}: ok ({len(got)} characters)")
        if failed:
            fail("the Discord messages are not as expected (run with --update after an intended change)")


if __name__ == "__main__":
    main()
