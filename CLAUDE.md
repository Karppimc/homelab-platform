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
infra/terraform/proxmox/   Terraform: VMs on Proxmox (bpg/proxmox provider)
ansible/                   Ansible: k3s installation, Argo CD bootstrap
  ansible.cfg
  inventory/hosts.yml
  inventory/group_vars/k3s_cluster/vars.yml
  inventory/group_vars/k3s_cluster/vault.yml   (Ansible Vault, encrypted)
  playbooks/k3s.yml
  playbooks/bootstrap-secrets.yml  (localhost; creates random in-cluster Secrets once, e.g. grafana-admin)
  playbooks/argocd.yml     (runs on localhost via kubeconfig; Helm install only on a fresh cluster)
platform/                  GitOps: everything here is deployed by Argo CD from GitHub main
  bootstrap/root.yaml      root Application, applied by the argocd playbook
  apps/                    one Application per component (argocd.yaml = self-management)
  argocd/values.yaml       Argo CD Helm values
  demo/values.yaml         podinfo demo app values (namespace demo)
  kyverno/values.yaml      Kyverno Helm values (namespace kyverno)
  monitoring/              kube-prometheus-stack, Loki and Alloy values (namespace monitoring)
README.md                  Public project description and roadmap
CLAUDE.md                  This file
```

Note: `group_vars` must live next to the inventory (or the playbook), otherwise Ansible silently ignores it.

Argo CD reads `platform/` from GitHub, not from the workstation: **changes take effect only after push**. The Argo CD chart version lives in `platform/apps/argocd.yaml`; the version in the playbook is only for bootstrapping a fresh cluster. The repo is public, so never commit plain Kubernetes Secrets (use Sealed Secrets or SOPS when needed).

## Workstation setup

All work happens in **WSL (Debian)**, not on the Windows filesystem. Ansible refuses `ansible.cfg` from world-writable `/mnt/c` paths, and SSH rejects keys there.

- Repo: `~/homelab-platform`
- Tools: Terraform, Ansible (via pipx, with `kubernetes==37.0.1` injected for `kubernetes.core.k8s`), kubectl, Helm v3.22.0 (`~/.local/bin`, SHA256-verified)
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
```

Full rebuild: `terraform destroy` → `terraform apply` → `ansible-playbook playbooks/k3s.yml` → `ansible-playbook playbooks/bootstrap-secrets.yml` → `ansible-playbook playbooks/argocd.yml`. After a rebuild the Argo CD admin password is regenerated in `argocd-initial-admin-secret`.

## Secrets – rules

- **Never print, log, commit or paste secret values**, including in chat or screenshots. If a secret is exposed, rotate it.
- Proxmox API token: in `infra/terraform/proxmox/terraform.tfvars` (git-ignored). Terraform user is `terraform@pve` with a least-privilege custom role `TerraformProv`. Rotate with `pveum user token remove/add`.
- k3s cluster token: in Ansible Vault (`vault.yml`). Vault password file: `~/.ansible-vault-pass` (outside the repo, also stored in a password manager).
- Terraform state (`*.tfstate`) is git-ignored and currently **local to one workstation**.
- Use `no_log: true` on Ansible tasks that handle secrets.
- In-cluster app credentials (Grafana admin) are generated by `bootstrap-secrets.yml` and live only in the cluster; a rebuild generates new ones. Charts that generate secrets with Helm `lookup` do not work under Argo CD (new value on every render): use `existingSecret` instead.

## Conventions

- **Conventional commits:** `feat(infra): ...`, `feat(ansible): ...`, `docs: ...`, `fix: ...`
- **LF line endings** enforced via `.gitattributes`
- **Pin versions** (providers, k3s, charts, images). No `latest`.
- **Idempotency:** playbooks must be safe to re-run (`creates:`, proper modules over raw shell where possible)
- **Least privilege** for every service account and token
- Every non-obvious design choice gets a short rationale in the README "Design decisions" table (ADRs planned in `docs/adr/`)

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
- [ ] **Phase 5 – Policy as code (in progress):** Kyverno 3.9.1 (v1.19.1) installed without policies; next: own policies in Audit mode, review PolicyReports, then Enforce with documented exceptions
- [ ] Phase 6 – Golden path service template + CI
- [ ] Phase 7 – Self-service CLI / Backstage

## Known gaps / TODO

- Terraform state is local → move to a remote backend before multiple people run Terraform
- Ingress TLS uses Traefik's self-signed default certificate → cert-manager with a local CA (the Argo CD Ingress already expects Secret `argocd-server-tls`)
- `*.home.arpa` names resolve only via the Windows hosts file → proper LAN DNS (router firmware or in-cluster DNS) later
- `local-path` volumes are pinned to one node (Prometheus on k3s-worker-2, Loki on k3s-worker-1): if that node is lost, so is its data, and moving the pod means deleting the PVC → replicated storage (e.g. Longhorn) if data ever matters
- Argo CD memory limits were sized for an empty cluster and have been raised twice (controller 1Gi, repo-server 512Mi) → re-check them when Kyverno and later components are added
- Alertmanager has no receivers, so alerts (e.g. OOMKilled restarts) reach nobody → add a receiver (email, Discord or similar); until then check `restartCount` and `lastState.terminated.reason` by hand. Short OOM spikes do not show in Prometheus memory graphs (30 s scrape interval)
- Argo CD polls GitHub every ~3 min; for an immediate sync use Refresh in the UI (a GitHub webhook would need a public endpoint)
