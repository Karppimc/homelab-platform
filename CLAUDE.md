# CLAUDE.md – homelab-platform

Context for Claude Code and for anyone joining the project. Read this before making changes.

## What this project is

A portfolio **Internal Developer Platform** built on repurposed hardware, demonstrating platform engineering: infrastructure as code, configuration management, GitOps, policy as code, observability by default and developer self-service. The README describes the public-facing story; this file describes how to work in the repo.

## Environment

| Item | Value |
|---|---|
| Hypervisor | Proxmox VE 9.2 on a Lenovo Y50-70 (i7-4720HQ, 16 GB RAM, 1 TB SATA SSD, ext4 + LVM-thin) |
| Proxmox host | `pve.home.arpa`, `https://192.168.1.50:8006`, node name `pve` |
| LAN | `192.168.1.0/24`, gateway/DNS `192.168.1.1` (ASUS RT-AC66U B1) |
| DHCP pool | `.2`–`.229`. **`.230`–`.254` is reserved for static server IPs** |
| VM template | ID `9000`, Ubuntu 24.04 cloud image, qemu-guest-agent baked in, empty machine-id |
| Storage | VM disks and cloud-init on `local-lvm` |

### k3s cluster

| Node | VM ID | IP | vCPU | RAM | Disk |
|---|---|---|---|---|---|
| k3s-cp-1 (control plane) | 201 | 192.168.1.230 | 2 | 4 GB | 30 GB |
| k3s-worker-1 | 211 | 192.168.1.231 | 3 | 4 GB | 50 GB |
| k3s-worker-2 | 212 | 192.168.1.232 | 3 | 4 GB | 50 GB |

- k3s version pinned to `v1.36.5+k3s1` in Ansible vars
- Default k3s components are enabled (Traefik, ServiceLB, local-path, metrics-server)
- The control plane is tainted `CriticalAddonsOnly=true:NoExecute` (set by the k3s playbook: `config.yaml` for fresh installs, `k8s_taint` for existing nodes). Only k3s system components tolerate it. **DaemonSets that must run on every node (node-exporter, Alloy) need a `CriticalAddonsOnly` toleration**; a toleration limited to `effect: NoSchedule` is not enough. Heavy workloads also keep a control-plane anti node affinity as a second guard. The control plane API server alone uses ~2.3 GiB after the Kyverno CRDs
- SSH user on all VMs: `santeri` (key-based only)
- Total RAM budget is tight: ~12 GB for VMs + ~2 GB for the host. Check memory before adding workloads or nodes.

The production website (karppimc.com) runs on a separate Raspberry Pi and is **out of scope**. Never touch it from this repo.

## Repository layout

```
infra/terraform/proxmox/   Terraform: VMs on Proxmox (bpg/proxmox provider); calls the k3s-node module per node
infra/terraform/modules/   Reusable Terraform modules, each with its own README (k3s-node = one VM)
ansible/                   Ansible: k3s installation, Argo CD bootstrap
  ansible.cfg
  inventory/hosts.yml
  inventory/group_vars/k3s_cluster/vars.yml
  inventory/group_vars/k3s_cluster/vault.yml   (Ansible Vault, encrypted)
  requirements.yml         pinned collections (kubernetes.core)
  playbooks/k3s.yml
  playbooks/bootstrap-secrets.yml  (localhost; creates in-cluster Secrets: random ones once, e.g. grafana-admin, and
                           vault-backed ones on every run, e.g. alertmanager-discord)
  playbooks/argocd.yml     (runs on localhost via kubeconfig; Helm install only on a fresh cluster)
platform/                  GitOps: everything here is deployed by Argo CD from GitHub main
  bootstrap/root.yaml      root Application, applied by the argocd playbook
  apps/                    one Application per component (argocd.yaml = self-management)
  argocd/values.yaml       Argo CD Helm values
  demo/values.yaml         podinfo demo app values (namespace demo)
  kyverno/values.yaml      Kyverno Helm values (namespace kyverno)
  alerts/                  PrometheusRules beyond the kube-prometheus-stack defaults (Argo CD applications, Kyverno
                           denials), namespace monitoring; Application `alerts`
  policies/                Kyverno ValidatingPolicy (policies.kyverno.io/v1, CEL); ClusterPolicy is deprecated in 1.19, do not use it
                           PolicyExceptions live here too but must use namespace kyverno (only namespace honoured)
  monitoring/              kube-prometheus-stack, Loki and Alloy values (namespace monitoring)
  namespace-baseline/      local Helm chart, the landing zone of one workload: Namespace, ResourceQuota, LimitRange,
                           NetworkPolicies (default deny) and an AppProject. values.schema.json validates workload files
  service-chart/           local Helm chart for services: Deployment, Service, ServiceMonitor from a values file that lives
                           in the service's repo (deploy/values.yaml). Must pass every policy without an exception
  apps/reference.yaml      the reference service: chart platform/service-chart from this repo, values from
                           Karppimc/reference-service (deploy/values.yaml); a release is an image.tag change in that repo
  workloads/               one values file per workload (name, owner, quota, sourceRepos); the ApplicationSet
                           platform/apps/workloads.yaml creates an Application baseline-<name> from each
tests/alerts/              promtool unit tests for the rules in platform/alerts/ (<name>_test.yaml per manifest)
tests/service-chart/       example values for the service chart (what a service's deploy/values.yaml looks like)
tests/policies/            Kyverno CLI tests, one directory per policy (kyverno-test.yaml + resources.yaml).
                           Kept outside platform/ on purpose: Argo CD would apply the test pods
.github/workflows/         validate.yml: CI checks on every PR and on main (required check: validate)
scripts/                   check-chart-policies.py: renders the charts in platform/apps and applies the Kyverno policies (CI and workstation)
                           check-namespace-baseline.sh: lints the baseline chart and validates its render per workload file
                           check-alert-rules.py: extracts the rule groups from platform/alerts/ and runs promtool
                           check rules and test rules with tests/alerts/; fails if an alert has no test
                           check-service-chart.sh: renders the service chart with tests/service-chart/values.yaml, then
                           kubeconform, schema negatives and the Kyverno policies
.yamllint                  yamllint config for the whole repo
README.md                  Public project description and roadmap
CLAUDE.md                  This file
```

Note: `group_vars` must live next to the inventory (or the playbook), otherwise Ansible silently ignores it.

Argo CD reads `platform/` from GitHub `main`, not from the workstation: **changes take effect only after the PR is merged to `main`**. The Argo CD chart version lives in `platform/apps/argocd.yaml`; the version in the playbook is only for bootstrapping a fresh cluster. The repo is public, so never commit plain Kubernetes Secrets (use Sealed Secrets or SOPS when needed).

## Workstation setup

All work happens in **WSL (Debian)**, not on the Windows filesystem. Ansible refuses `ansible.cfg` from world-writable `/mnt/c` paths, and SSH rejects keys there.

- Repo: `~/homelab-platform`
- Tools: Terraform, Ansible (via pipx, with `kubernetes==37.0.1` injected for `kubernetes.core.k8s`), kubectl, Helm v3.22.0 (`~/.local/bin`, SHA256-verified)
- Lint and test tools, same versions as CI (`.github/workflows/validate.yml`): ansible-lint 26.10.1 (pipx, with `ansible-core==2.19.14` pinned in its venv), yamllint 1.38.0 (pipx), Kyverno CLI v1.19.1 and kubeconform v0.8.0 (`~/.local/bin`, SHA256-verified). `scripts/check-alert-rules.py` needs `promtool` 3.15.0 (from the Prometheus release tarball; keep it equal to the cluster's Prometheus). `scripts/check-chart-policies.py` also needs Helm and PyYAML (CI pins PyYAML 6.0.3)
- `KUBECONFIG=~/.kube/homelab.yaml` (fetched by the k3s playbook, exported in `~/.bashrc`). Without it kubectl falls back to `~/.kube/config`, which points at an old Docker Desktop cluster
- SSH key loaded via `keychain`

## Common commands

```bash
# Infrastructure
cd infra/terraform/proxmox
terraform plan            # always read the plan before applying
terraform apply

# Cluster
cd ansible
ansible all -m ping
ansible-playbook playbooks/k3s.yml
ansible-playbook playbooks/bootstrap-secrets.yml
ansible-playbook playbooks/argocd.yml

# Argo CD UI: https://argocd.home.arpa (Windows hosts file → 192.168.1.230),
# user admin, password in password manager. TLS ends at Traefik (server.insecure).
# Fallback if the Ingress is broken:
kubectl -n argocd port-forward svc/argocd-server 8080:80   # http://localhost:8080

# Grafana UI: https://grafana.home.arpa (hosts file), user admin, password:
kubectl -n monitoring get secret grafana-admin -o jsonpath='{.data.admin-password}' | base64 -d

# Verify
kubectl get nodes -o wide
kubectl get pods -A

# Checks that CI runs (workflow validate); run them before opening a PR
terraform -chdir=infra/terraform fmt -check -recursive   # root and modules
terraform -chdir=infra/terraform/proxmox validate
yamllint .
(cd ansible && ansible-lint)
scripts/check-namespace-baseline.sh   # helm lint + render + kubeconform for every file in platform/workloads
scripts/check-service-chart.sh        # service chart: lint, render, kubeconform, schema negatives, policies
kyverno test tests/policies
scripts/check-alert-rules.py          # promtool check + unit tests for platform/alerts (needs promtool on PATH)
scripts/check-chart-policies.py   # helm template every chart in platform/apps, then kyverno apply (hook Jobs included)
kubeconform -strict -summary -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  platform/apps platform/bootstrap platform/policies platform/alerts
```

Full rebuild: `terraform destroy` → `terraform apply` → `ansible-playbook playbooks/k3s.yml` → `ansible-playbook playbooks/bootstrap-secrets.yml` → `ansible-playbook playbooks/argocd.yml`. After a rebuild the Argo CD admin password is regenerated in `argocd-initial-admin-secret`.

## Secrets – rules

- **Never print, log, commit or paste secret values**, including in chat or screenshots. If a secret is exposed, rotate it.
- Proxmox API token: in `infra/terraform/proxmox/terraform.tfvars` (git-ignored). Terraform user is `terraform@pve` with a least-privilege custom role `TerraformProv`. Rotate with `pveum user token remove/add`.
- k3s cluster token: in Ansible Vault (`vault.yml`). Vault password file: `~/.ansible-vault-pass` (outside the repo, also stored in a password manager).
- Terraform state (`*.tfstate`) is git-ignored and currently **local to one workstation**.
- Use `no_log: true` on Ansible tasks that handle secrets.
- In-cluster app credentials (Grafana admin) are generated by `bootstrap-secrets.yml` and live only in the cluster; a rebuild generates new ones. Charts that generate secrets with Helm `lookup` do not work under Argo CD (new value on every render): use `existingSecret` instead.
- Alertmanager's Discord webhook URL is `vault_alertmanager_discord_webhook_url` in Ansible Vault; `bootstrap-secrets.yml` writes it to the Secret `alertmanager-discord` (namespace monitoring), which Alertmanager mounts and reads as a file. Alertmanager does not start without the Secret: after a rebuild run `bootstrap-secrets.yml` before `argocd.yml`. To rotate: new webhook in Discord, `ansible-vault edit`, re-run the playbook

## Conventions

- **Protected `main`:** the ruleset `golden-path: main` (managed by `/golden-path:setup-branch-policy`) blocks direct pushes, force pushes and deletion for everyone, the owner included; there are no bypass actors. Every change goes through a PR with a green `validate` check and resolved conversations, merged by squash; the head branch is deleted after the merge. Approvals are 0 because the repo has one owner, whose merge is the approval. Break glass (e.g. CI itself is broken): an admin sets the ruleset to disabled in the repo settings, fixes, and re-enables it
- **Conventional commits:** `feat(infra): ...`, `feat(ansible): ...`, `docs: ...`, `fix: ...`
- **LF line endings** enforced via `.gitattributes`
- **Pin versions** (providers, k3s, charts, images). No `latest`.
- **Idempotency:** playbooks must be safe to re-run (`creates:`, proper modules over raw shell where possible)
- **Least privilege** for every service account and token
- Every non-obvious design choice gets a short rationale in the README "Design decisions" table (ADRs planned in `docs/adr/`)
- **Every workload must pass the Kyverno policies:** memory request + limit on every container (including init and Helm hook containers), pinned image tag, `runAsNonRoot: true` with a numeric `runAsUser` when the image sets `USER` by name. Before adding a chart, bumping a chart version or changing a policy, run `scripts/check-chart-policies.py` (CI runs it too): it renders every chart and checks all workloads, **including Helm hook Jobs**: background scans never see hooks, and a rejected hook blocks the whole sync (for Argo CD itself, that means break glass)
- **New workloads go through the namespace baseline:** add `platform/workloads/<name>.yaml` (file name = `name`) and an Application with `project: <name>`; do not use `CreateNamespace=true` or the `default` project for workloads. The baseline denies egress out of the namespace except DNS: a workload that calls something outside adds its own NetworkPolicy. Removing a workload file does not delete its namespace (`preserveResourcesOnDeletion`, `Prune=false` on the Namespace)
- **Services use the platform chart:** a service's Application takes `platform/service-chart` from this repo and `deploy/values.yaml` from the service's repo (`$values` ref); both repos go in the workload's `sourceRepos`. Change the chart, not the service, when a policy changes; `scripts/check-service-chart.sh` must pass without exceptions
- **Standard labels:** `require-standard-labels` (Deny) requires `app.kubernetes.io/name`, `part-of` and `managed-by` on Deployments, StatefulSets, DaemonSets, Jobs, CronJobs, their pod templates (and a CronJob's job template) and Pods, outside `kube-system` and `kyverno`. A chart that does not label its pods needs chart values (`podLabels` and the like) or a narrow PolicyException before it can be deployed. An ad hoc `kubectl run` pod needs the three labels too (`--labels`). `scripts/check-chart-policies.py` prints violations of audit-only policies as warnings and fails only on policies that deny
- **Every policy change comes with test cases** in `tests/policies/<policy>/`: at least one good, one bad and the edge cases. A resource that a policy must not match (excluded namespace, PolicyException) is asserted with `result: skip`; any other expected result passes silently for it
- **CI versions are pinned in one place**, the `env` block of `.github/workflows/validate.yml`: actions by commit SHA, binaries by SHA256, the CRD schema catalog by commit. Keep the Kyverno CLI version equal to the cluster's
- CI has no vault password: `ansible-lint` runs with a placeholder password file, which is enough because the syntax check never decrypts `vault.yml`. Never add the real password as a GitHub secret for linting
- **Alerts:** everything except `Watchdog`, `InfoInhibitor` and `severity: info` goes to Discord. New platform rules go in `platform/alerts/` as PrometheusRules, and **every rule change comes with test cases** in `tests/alerts/` (it fires when it should and stays quiet otherwise); `scripts/check-alert-rules.py` refuses an alert without a test. Also evaluate the expression against the live Prometheus before the PR: the tests use made-up series, the cluster has the real label names. Remember that `increase()` does not see a counter series that has just appeared (see the comment in `platform/alerts/kyverno.yaml`). Local `ansible-lint` cannot resolve `kubernetes.core` on this workstation; CI can, use `ansible-playbook --syntax-check` locally
- When triggering a sync by patching `.operation`, pass the app's `syncOptions` too (e.g. `ServerSideApply=true`); otherwise Argo CD falls back to client-side apply and large CRDs fail

## Working style

- The project owner prefers **step-by-step progression**: one step at a time, explain *why* as well as *how*, then wait for confirmation before moving on.
- Prefer teaching over doing everything silently; this is a learning and portfolio project.
- Communicate in the user's language (usually Finnish); code, comments, commits and docs in English.

## Status and roadmap

- [x] Phase 0 – Foundations: Proxmox host, networking, repo
- [x] Phase 1 – Infrastructure as code: Terraform user, cloud-init template, VM provisioning
- [x] Phase 2 – Kubernetes: 3-node k3s cluster via Terraform + Ansible
- [x] Phase 3 – GitOps: Argo CD (chart 10.10.2 / v3.5.4), app-of-apps, self-management, podinfo demo, UI via Traefik Ingress
- [x] Phase 4 – Observability: kube-prometheus-stack 92.3.0, Loki 7.3.0 (single binary), Alloy 1.13.1, podinfo ServiceMonitor
- [x] Phase 5 – Policy as code: Kyverno 3.9.1 (v1.19.1); require-memory-limits, disallow-latest-tag, require-run-as-non-root enforced (Deny, failurePolicy Fail); require-standard-labels enforced as well since #27 (Deny; also covers Jobs and CronJobs); two exceptions (Alloy runs as root; the podinfo chart cannot set the standard labels); control plane tainted
- [x] Phase 6 – Golden path: Karppimc/service-template (Go, distroless, CI with Trivy, GHCR), namespace baseline, platform service chart; Karppimc/reference-service runs in namespace `reference` (Application `reference`, values from the service repo)
- [ ] Phase 7 – Self-service CLI / Backstage

## Known gaps / TODO

- Terraform state is local → move to a remote backend before multiple people run Terraform
- Ingress TLS uses Traefik's self-signed default certificate → cert-manager with a local CA (the Argo CD Ingress already expects Secret `argocd-server-tls`)
- `*.home.arpa` names resolve only via the Windows hosts file → proper LAN DNS (router firmware or in-cluster DNS) later
- `local-path` volumes are pinned to one node (Prometheus on k3s-worker-2, Loki on k3s-worker-1): if that node is lost, so is its data, and moving the pod means deleting the PVC → replicated storage (e.g. Longhorn) if data ever matters
- Argo CD memory limits were sized for an empty cluster and have been raised twice (controller 1Gi, repo-server 512Mi); with Kyverno added the controller idles around 460 Mi → re-check when later components are added
- kube-prometheus-stack admission webhook hook Jobs race with Argo CD hook tracking (`hook-succeeded` deletes the Job before Argo records it: "waiting for deletion of hook" or "Job is missing"). Harmless so far → replace the hook Jobs with cert-manager (`prometheusOperator.admissionWebhooks.certManager`) once cert-manager is installed
- The chart policy check (`scripts/check-chart-policies.py`) sees only what `helm template` renders: pods that an operator creates from a custom resource (Prometheus, Alertmanager) are checked only by background scans in the cluster. It also depends on the public Helm repositories being reachable from CI
- Alerts go to one Discord channel and nothing checks that the channel still works: if the webhook is deleted, alerts are lost silently (Alertmanager logs the error, `AlertmanagerFailedToSendAlerts` fires into the same dead channel). Short OOM spikes do not show in Prometheus memory graphs (30 s scrape interval).
- Argo CD polls GitHub every ~3 min; for an immediate sync use Refresh in the UI (a GitHub webhook would need a public endpoint)
