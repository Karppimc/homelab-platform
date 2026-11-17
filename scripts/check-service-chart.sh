#!/usr/bin/env bash
# Lint the platform's service chart, render it with the example values and check
# the result with kubeconform and the Kyverno policies. A service rendered from
# this chart must pass every policy without an exception.
# Needs helm, kubeconform and kyverno.
#
# Usage: check-service-chart.sh [values-file]
# Without an argument it uses the example values in tests/service-chart/. A
# service's CI passes its own deploy/values.yaml, so a values file that the
# platform would refuse fails in the service's pull request.
#
# CRD_CATALOG_REF pins the CRD schema catalog (ServiceMonitor); CI sets it.
set -euo pipefail

# Resolve the values file before changing directory: it may be relative to the caller
values=$(realpath "${1:-$(dirname "$0")/../tests/service-chart/values.yaml}")
cd "$(dirname "$0")/.."
chart=platform/service-chart
catalog="https://raw.githubusercontent.com/datreeio/CRDs-catalog/${CRD_CATALOG_REF:-main}"

# kubeconform only reads files with a YAML extension
rendered=$(mktemp --suffix=.yaml)
trap 'rm -f "${rendered}"' EXIT

helm lint "${chart}" --values "${values}" --quiet
helm template example "${chart}" --namespace example --values "${values}" >"${rendered}"

echo "=== kubeconform"
kubeconform -strict -summary \
  -schema-location default \
  -schema-location "${catalog}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
  "${rendered}"
# Deployment, Service and ServiceMonitor: fewer means the render went wrong
if [ "$(grep -c '^kind:' "${rendered}")" -lt 3 ]; then
  echo "ERROR: expected at least 3 rendered resources" >&2
  exit 1
fi

echo "=== ingress"
# Without ingress.host there is no Ingress; with it, a valid one. Covered whatever
# the values file says, so a service's CI checks both shapes too
with_ingress=$(mktemp --suffix=.yaml)
trap 'rm -f "${rendered}" "${with_ingress}"' EXIT
helm template example "${chart}" --namespace example --values "${values}" \
  --set-string ingress.host= | grep -q '^kind: Ingress$' && {
  echo "ERROR: an Ingress was rendered without ingress.host" >&2
  exit 1
}
helm template example "${chart}" --namespace example --values "${values}" \
  --set-string ingress.host=example.home.arpa >"${with_ingress}"
grep -q '^kind: Ingress$' "${with_ingress}" || {
  echo "ERROR: no Ingress rendered with ingress.host set" >&2
  exit 1
}
# The platform's endpoints must not be published: a Middleware that refuses every
# request, and an Ingress that sends exactly those paths through it
if ! grep -q '^kind: Middleware$' "${with_ingress}" ||
  ! grep -q 'router.middlewares: example-example-private-paths@kubernetescrd' "${with_ingress}"; then
  echo "ERROR: no Middleware that keeps the metrics and health paths private" >&2
  exit 1
fi
for path in /metrics /healthz /readyz; do
  grep -A1 -- "- path: ${path}\$" "${with_ingress}" | grep -q 'pathType: Exact' || {
    echo "ERROR: ${path} is not kept private by the Ingress" >&2
    exit 1
  }
done
kubeconform -strict -summary \
  -schema-location default \
  -schema-location "${catalog}/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json" \
  "${with_ingress}"

echo "=== values schema"
# The schema must refuse what the policies would refuse later
reject() {
  if helm template example "${chart}" --namespace example --values "${values}" "$@" >/dev/null 2>&1; then
    echo "ERROR: the values schema accepted: $*" >&2
    exit 1
  fi
  echo "rejected as expected: $*"
}
reject --set-string image.tag=latest
reject --set-string image.tag=
reject --set-string name=
reject --set resources.limits=null
reject --set-string ingress.host=example.com
reject --set-string ingress.host=Example.home.arpa
reject --set-string ingress.host=home.arpa

echo "=== kyverno policies"
# Policies are passed as files: for a directory of these policies kyverno loads
# nothing and exits 0. No exceptions are passed: the chart must comply by itself
mapfile -t policies < <(grep -l '^kind: ValidatingPolicy$' platform/policies/*.yaml)
output=$(kyverno apply "${policies[@]}" --resource "${rendered}" --remove-color 2>&1) || {
  echo "${output}"
  echo "ERROR: the rendered service violates a policy" >&2
  exit 1
}
echo "${output}"
applied=$(sed -n 's/^Applying \([0-9]*\) policy rule.*/\1/p' <<<"${output}")
if [ -z "${applied}" ] || [ "${applied}" -lt "${#policies[@]}" ]; then
  echo "ERROR: kyverno did not apply all ${#policies[@]} policies" >&2
  exit 1
fi
