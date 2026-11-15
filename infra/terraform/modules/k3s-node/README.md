# k3s-node

Creates one k3s node as a Proxmox VM cloned from a cloud-init template.

The VM gets a static IPv4 address, one user with an SSH key (through cloud-init), the QEMU guest agent enabled and the tags `terraform`, `k3s` and its role. The module creates the VM only: k3s itself is installed by Ansible.

## Usage

```hcl
module "k3s_node" {
  source = "../modules/k3s-node" # path from the calling configuration

  name  = "k3s-worker-1"
  vm_id = 211
  role  = "worker"

  node_name    = "pve"
  datastore_id = "local-lvm"
  template_id  = 9000

  ip                    = "192.168.1.231"
  network_prefix_length = 24
  gateway               = "192.168.1.1"
  dns_servers           = ["192.168.1.1"]

  cores  = 3
  memory = 4096
  disk   = 50

  username       = "santeri"
  ssh_public_key = file(pathexpand("~/.ssh/id_ed25519.pub"))
}
```

For several nodes, call the module with `for_each` over a map of nodes, as `infra/terraform/proxmox/main.tf` does.

The module has no `provider` block: the calling configuration configures `bpg/proxmox`.

## Requirements

| Name | Version |
|---|---|
| Terraform | `~> 1.16` |
| `bpg/proxmox` | `~> 0.117` |

## Inputs

All inputs are required: the module has no defaults, so nothing about the environment is assumed.

| Name | Description | Type | Validation |
|---|---|---|---|
| `name` | Name of the VM, also its hostname. | `string` | kebab-case, starts with a letter |
| `vm_id` | Proxmox VM ID of the node. Must be unique in the Proxmox cluster. | `number` | whole number, 100–999999999 |
| `role` | Role of the node in the k3s cluster, added to the VM as a tag. | `string` | `control-plane` or `worker` |
| `node_name` | Name of the Proxmox node the VM is created on. | `string` | valid host name |
| `datastore_id` | Proxmox datastore that holds both the VM disk and the cloud-init drive. | `string` | not empty |
| `template_id` | VM ID of the cloud-init template the VM is cloned from. | `number` | whole number, 100–999999999 |
| `ip` | Static IPv4 address of the VM, without a prefix length. | `string` | valid IPv4 address |
| `network_prefix_length` | Prefix length of the subnet the VM is in (24 means /24). | `number` | whole number, 1–32 |
| `gateway` | IPv4 address of the default gateway of the VM. | `string` | valid IPv4 address |
| `dns_servers` | IPv4 addresses of the DNS servers the VM uses. | `list(string)` | non-empty, valid IPv4 addresses |
| `cores` | Number of CPU cores of the VM. | `number` | whole number, at least 1 |
| `memory` | Memory of the VM in MB. | `number` | whole number, at least 1024 |
| `disk` | Size of the VM disk in GB. | `number` | whole number, at least 10 |
| `username` | Name of the user that cloud-init creates on the VM. | `string` | valid Linux user name |
| `ssh_public_key` | SSH public key (the key itself, not a path) that cloud-init installs for the user. | `string` | OpenSSH public key format |

## Outputs

| Name | Description |
|---|---|
| `name` | Name of the VM. |
| `vm_id` | Proxmox VM ID of the node. |
| `ipv4_address` | Static IPv4 address of the VM, without a prefix length. |
