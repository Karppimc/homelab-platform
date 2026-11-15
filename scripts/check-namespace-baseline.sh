#!/usr/bin/env bash
# Lint the namespace baseline chart and validate what it renders for every
# workload file in platform/workloads/. Needs helm and kubeconform.
#
# CRD_CATALOG_REF pins the CRD schema catalog (AppProject); CI sets it.
set -euo pipefail

cd "$(dirname "$0")/.."
chart=platform/namespace-baseline
catalog="https://raw.githubusercontent.com/datreeio/CRDs-catalog/${CRD_CATALOG_REF:-main}"

shopt -s nullglob
files=(platform/workloads/*.yaml)
if [ "${#files[@]}" -eq 0 ]; then
  echo "ERROR: no workload files in platform/workloads/" >&2
  exit 1
fi

for file in "${files[@]}"; do
  echo "=== ${file}"
  # The ApplicationSet names things after the name in the file; keep the file
  # name equal to it so a workload is easy to find
  name=$(sed -n 's/^name:[[:space:]]*//p' "${file}")
  if [ "${name}" != "$(basename "${file}" .yaml)" ]; then
    echo "ERROR: ${file} sets name '${name}'; the file must be called ${name}.yaml" >&2
    exit 1
  fi
  helm lint "${chart}" --values "${file}" --quiet
  helm template "baseline-${name}" "${chart}" --values "${file}" |
    kubeconform -strict -summary \
      -schema-location default \
      -schema-location "${catalog}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json"
done
