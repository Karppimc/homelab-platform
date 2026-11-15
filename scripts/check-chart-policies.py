#!/usr/bin/env python3
"""Render the Helm charts that Argo CD deploys and check them against the Kyverno policies.

For every Application in platform/apps/ that has a Helm chart source, the script

1. renders the chart with `helm template`, using the chart version, release name,
   values files and namespace from the Application (Helm hooks included, test
   hooks left out because Argo CD does not run them),
2. turns the pod template of every workload (Deployment, StatefulSet, DaemonSet,
   ReplicaSet, Job, CronJob, Pod) into a Pod, because the policies match Pods,
3. runs `kyverno apply` with the policies and PolicyExceptions in platform/policies/.

It exits non-zero when a workload violates a policy, and also when the check
could not have found a violation: a chart without workloads, or a run in which
Kyverno evaluated no policy rule.

Not covered: pods that an operator creates from a custom resource (Prometheus,
Alertmanager). They are not in the rendered output; background scans in the
cluster still see them.

Needs helm, kyverno and PyYAML. Run from anywhere:

    scripts/check-chart-policies.py
"""

import argparse
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import yaml

REPO_ROOT = Path(__file__).resolve().parent.parent
WORKLOADS_WITH_TEMPLATE = ("Deployment", "StatefulSet", "DaemonSet", "ReplicaSet", "Job")


class Loader(yaml.SafeLoader):
    """SafeLoader that also accepts the YAML 1.1 value tag (a bare "=")."""


# Some CRDs and dashboards contain a plain "=" scalar, which PyYAML refuses to load
Loader.add_constructor("tag:yaml.org,2002:value", lambda loader, node: loader.construct_scalar(node))


def fail(message):
    print(f"ERROR: {message}", file=sys.stderr)
    sys.exit(1)


def load_documents(text):
    return [doc for doc in yaml.load_all(text, Loader=Loader) if isinstance(doc, dict)]


def kube_version(vars_file):
    """The Kubernetes version of the cluster, from the pinned k3s version (v1.36.5+k3s1 -> 1.36.5)."""
    k3s_version = yaml.safe_load(vars_file.read_text())["k3s_version"]
    match = re.fullmatch(r"v(\d+\.\d+\.\d+)\+k3s\d+", k3s_version)
    if not match:
        fail(f"cannot read a Kubernetes version from k3s_version '{k3s_version}' in {vars_file}")
    return match.group(1)


def helm_charts(apps_dir):
    """One dict per Helm chart source in the Application manifests."""
    charts = []
    for path in sorted(apps_dir.glob("*.yaml")):
        for doc in load_documents(path.read_text()):
            if doc.get("kind") != "Application":
                continue
            spec = doc["spec"]
            sources = spec.get("sources") or [spec["source"]]
            # valueFiles such as $values/platform/x.yaml point into the source with "ref: values"
            refs = [source["ref"] for source in sources if "ref" in source]
            for source in sources:
                if "chart" not in source:
                    continue
                if not source["repoURL"].startswith("https://"):
                    fail(f"{path}: only https:// Helm repositories are supported, got {source['repoURL']}")
                helm = source.get("helm") or {}
                values = []
                for value_file in helm.get("valueFiles") or []:
                    ref = next((r for r in refs if value_file.startswith(f"${r}/")), None)
                    if ref is None:
                        fail(f"{path}: cannot resolve values file '{value_file}'")
                    values.append(REPO_ROOT / value_file[len(ref) + 2:])
                charts.append({
                    "app": doc["metadata"]["name"],
                    "repo": source["repoURL"],
                    "chart": source["chart"],
                    "version": source["targetRevision"],
                    "release": helm.get("releaseName") or doc["metadata"]["name"],
                    "namespace": spec["destination"]["namespace"],
                    "values": values,
                })
    return charts


def render(chart, kubernetes_version):
    command = [
        "helm", "template", chart["release"], chart["chart"],
        "--repo", chart["repo"],
        "--version", chart["version"],
        "--namespace", chart["namespace"],
        "--kube-version", kubernetes_version,
        "--skip-tests",
    ]
    for value_file in chart["values"]:
        command += ["--values", str(value_file)]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    if result.returncode != 0:
        fail(f"helm template failed for {chart['app']}:\n{result.stderr}")
    return load_documents(result.stdout)


def pods(documents, default_namespace):
    """The pod template of every workload as a Pod, so that policies matching Pods apply."""
    result = []
    for doc in documents:
        kind = doc.get("kind")
        metadata = doc.get("metadata") or {}
        if kind in WORKLOADS_WITH_TEMPLATE:
            template = doc["spec"]["template"]
        elif kind == "CronJob":
            template = doc["spec"]["jobTemplate"]["spec"]["template"]
        elif kind == "Pod":
            template = {"metadata": metadata, "spec": doc["spec"]}
        else:
            continue
        hook = (metadata.get("annotations") or {}).get("helm.sh/hook")
        result.append({
            "hook": hook,
            "manifest": {
                "apiVersion": "v1",
                "kind": "Pod",
                "metadata": {
                    # Kind in the name keeps a Deployment and a Job of the same name apart
                    "name": f"{kind.lower()}-{metadata['name']}",
                    # Charts often leave the namespace out and rely on the release namespace
                    "namespace": metadata.get("namespace") or default_namespace,
                    "labels": (template.get("metadata") or {}).get("labels") or {},
                },
                "spec": template["spec"],
            },
        })
    return result


def policy_files(policies_dir):
    """Policy and exception files, told apart by kind. An unknown kind is an error."""
    policies, exceptions = [], []
    for path in sorted(policies_dir.glob("*.yaml")):
        kinds = {doc.get("kind") for doc in load_documents(path.read_text())}
        if kinds == {"ValidatingPolicy"}:
            policies.append(path)
        elif kinds == {"PolicyException"}:
            exceptions.append(path)
        else:
            fail(f"{path}: expected only ValidatingPolicy or only PolicyException, found {sorted(kinds)}")
    if not policies:
        fail(f"no ValidatingPolicy found in {policies_dir}")
    return policies, exceptions


def kyverno_apply(policies, exceptions, resources_file):
    command = ["kyverno", "apply", *map(str, policies), "--resource", str(resources_file), "--remove-color"]
    for exception in exceptions:
        command += ["--exception", str(exception)]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    output = (result.stdout + result.stderr).strip()
    print(output)
    # Kyverno exits 0 when it loaded no policy at all, so check that it really evaluated them
    match = re.search(r"Applying (\d+) policy rule", output)
    if not match or int(match.group(1)) < len(policies):
        fail(f"kyverno did not apply all {len(policies)} policies; the check would pass without checking anything")
    return result.returncode == 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--apps", type=Path, default=REPO_ROOT / "platform/apps",
                        help="directory with the Argo CD Application manifests")
    parser.add_argument("--policies", type=Path, default=REPO_ROOT / "platform/policies",
                        help="directory with the Kyverno policies and exceptions")
    parser.add_argument("--kube-version",
                        help="Kubernetes version to render for (default: from k3s_version in the Ansible vars)")
    args = parser.parse_args()

    kubernetes_version = args.kube_version or kube_version(
        REPO_ROOT / "ansible/inventory/group_vars/k3s_cluster/vars.yml")
    policies, exceptions = policy_files(args.policies)
    charts = helm_charts(args.apps)
    if not charts:
        fail(f"no Helm chart found in the Applications in {args.apps}")

    print(f"Kubernetes {kubernetes_version}, {len(policies)} policies, {len(exceptions)} exceptions, "
          f"{len(charts)} charts\n")
    failed = []
    for chart in charts:
        print(f"=== {chart['app']}: {chart['chart']} {chart['version']} (namespace {chart['namespace']})")
        workloads = pods(render(chart, kubernetes_version), chart["namespace"])
        if not workloads:
            fail(f"{chart['app']}: the rendered chart has no workloads; nothing would be checked")
        for workload in workloads:
            suffix = f"  [hook: {workload['hook']}]" if workload["hook"] else ""
            print(f"  {workload['manifest']['metadata']['name']}{suffix}")
        with tempfile.NamedTemporaryFile("w", suffix=".yaml") as resources:
            yaml.safe_dump_all([w["manifest"] for w in workloads], resources)
            resources.flush()
            if not kyverno_apply(policies, exceptions, resources.name):
                failed.append(chart["app"])
        print()

    if failed:
        fail(f"policy violations in: {', '.join(failed)}")
    print(f"All {len(charts)} charts pass the policies.")


if __name__ == "__main__":
    main()
