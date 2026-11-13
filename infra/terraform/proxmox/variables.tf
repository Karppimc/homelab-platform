variable "proxmox_endpoint" {
  description = "URL of the Proxmox VE API."
  type        = string
  default     = "https://192.168.1.50:8006/"
}

variable "proxmox_api_token" {
  description = "Proxmox API token in the form user@realm!tokenid=secret. Set it in terraform.tfvars (git-ignored)."
  type        = string
  sensitive   = true
}

variable "node_name" {
  description = "Name of the Proxmox node the VMs are created on."
  type        = string
  default     = "pve"
}

variable "template_id" {
  description = "VM ID of the cloud-init template the nodes are cloned from."
  type        = number
  default     = 9000
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key that cloud-init installs for the VM user."
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "gateway" {
  description = "IPv4 address of the LAN gateway. Also used as the DNS server of the VMs."
  type        = string
  default     = "192.168.1.1"

  validation {
    condition     = can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", var.gateway)) && can(cidrhost("${var.gateway}/32", 0))
    error_message = "The gateway must be a valid IPv4 address without a prefix length, e.g. 192.168.1.1."
  }
}

variable "k3s_nodes" {
  description = "Nodes of the k3s cluster, keyed by VM name. Add or remove an entry to resize the cluster. Memory is in MB, disk in GB."
  type = map(object({
    vm_id  = number
    role   = string
    ip     = string
    cores  = number
    memory = number
    disk   = number
  }))
  default = {
    "k3s-cp-1"     = { vm_id = 201, role = "control-plane", ip = "192.168.1.230", cores = 2, memory = 4096, disk = 30 }
    "k3s-worker-1" = { vm_id = 211, role = "worker", ip = "192.168.1.231", cores = 3, memory = 4096, disk = 50 }
    "k3s-worker-2" = { vm_id = 212, role = "worker", ip = "192.168.1.232", cores = 3, memory = 4096, disk = 50 }
  }

  validation {
    condition     = alltrue([for node in values(var.k3s_nodes) : contains(["control-plane", "worker"], node.role)])
    error_message = "Each node's role must be \"control-plane\" or \"worker\"."
  }

  validation {
    condition = alltrue([
      for node in values(var.k3s_nodes) :
      can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", node.ip)) && can(cidrhost("${node.ip}/32", 0))
    ])
    error_message = "Each node's ip must be a valid IPv4 address without a prefix length, e.g. 192.168.1.230."
  }

  validation {
    condition     = alltrue([for node in values(var.k3s_nodes) : node.cores >= 1 && floor(node.cores) == node.cores])
    error_message = "Each node's cores must be a whole number of at least 1."
  }

  validation {
    condition     = alltrue([for node in values(var.k3s_nodes) : node.memory >= 1024 && floor(node.memory) == node.memory])
    error_message = "Each node's memory must be a whole number of at least 1024 (MB)."
  }

  validation {
    condition     = alltrue([for node in values(var.k3s_nodes) : node.disk >= 10 && floor(node.disk) == node.disk])
    error_message = "Each node's disk must be a whole number of at least 10 (GB)."
  }
}
