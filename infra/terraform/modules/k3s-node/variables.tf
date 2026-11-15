variable "name" {
  description = "Name of the VM, also its hostname. Lowercase letters, digits and hyphens."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,61}[a-z0-9]$", var.name))
    error_message = "The name must be kebab-case: lowercase letters, digits and hyphens, starting with a letter."
  }
}

variable "vm_id" {
  description = "Proxmox VM ID of the node. Must be unique in the Proxmox cluster."
  type        = number

  validation {
    condition     = var.vm_id >= 100 && var.vm_id <= 999999999 && floor(var.vm_id) == var.vm_id
    error_message = "The vm_id must be a whole number from 100 to 999999999."
  }
}

variable "role" {
  description = "Role of the node in the k3s cluster, added to the VM as a tag."
  type        = string

  validation {
    condition     = contains(["control-plane", "worker"], var.role)
    error_message = "The role must be \"control-plane\" or \"worker\"."
  }
}

variable "node_name" {
  description = "Name of the Proxmox node the VM is created on."
  type        = string

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?$", var.node_name))
    error_message = "The node_name must be a valid host name: letters, digits and hyphens, not starting or ending with a hyphen."
  }
}

variable "datastore_id" {
  description = "Proxmox datastore that holds both the VM disk and the cloud-init drive."
  type        = string

  validation {
    condition     = length(trimspace(var.datastore_id)) > 0
    error_message = "The datastore_id must not be empty."
  }
}

variable "template_id" {
  description = "VM ID of the cloud-init template the VM is cloned from."
  type        = number

  validation {
    condition     = var.template_id >= 100 && var.template_id <= 999999999 && floor(var.template_id) == var.template_id
    error_message = "The template_id must be a whole number from 100 to 999999999."
  }
}

variable "ip" {
  description = "Static IPv4 address of the VM, without a prefix length."
  type        = string

  validation {
    condition     = can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", var.ip)) && can(cidrhost("${var.ip}/32", 0))
    error_message = "The ip must be a valid IPv4 address without a prefix length, e.g. 192.168.1.230."
  }
}

variable "network_prefix_length" {
  description = "Prefix length of the subnet the VM is in, appended to its IPv4 address (24 means /24)."
  type        = number

  validation {
    condition     = var.network_prefix_length >= 1 && var.network_prefix_length <= 32 && floor(var.network_prefix_length) == var.network_prefix_length
    error_message = "The network_prefix_length must be a whole number from 1 to 32."
  }
}

variable "gateway" {
  description = "IPv4 address of the default gateway of the VM."
  type        = string

  validation {
    condition     = can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", var.gateway)) && can(cidrhost("${var.gateway}/32", 0))
    error_message = "The gateway must be a valid IPv4 address without a prefix length, e.g. 192.168.1.1."
  }
}

variable "dns_servers" {
  description = "IPv4 addresses of the DNS servers the VM uses."
  type        = list(string)

  validation {
    condition = length(var.dns_servers) > 0 && alltrue([
      for server in var.dns_servers :
      can(regex("^\\d{1,3}(\\.\\d{1,3}){3}$", server)) && can(cidrhost("${server}/32", 0))
    ])
    error_message = "The dns_servers must be a non-empty list of valid IPv4 addresses, e.g. [\"192.168.1.1\"]."
  }
}

variable "cores" {
  description = "Number of CPU cores of the VM."
  type        = number

  validation {
    condition     = var.cores >= 1 && floor(var.cores) == var.cores
    error_message = "The cores must be a whole number of at least 1."
  }
}

variable "memory" {
  description = "Memory of the VM in MB."
  type        = number

  validation {
    condition     = var.memory >= 1024 && floor(var.memory) == var.memory
    error_message = "The memory must be a whole number of at least 1024 (MB)."
  }
}

variable "disk" {
  description = "Size of the VM disk in GB."
  type        = number

  validation {
    condition     = var.disk >= 10 && floor(var.disk) == var.disk
    error_message = "The disk must be a whole number of at least 10 (GB)."
  }
}

variable "username" {
  description = "Name of the user that cloud-init creates on the VM."
  type        = string

  validation {
    condition     = can(regex("^[a-z_][a-z0-9_-]{0,31}$", var.username))
    error_message = "The username must be a valid Linux user name: lowercase letters, digits, - and _, starting with a letter or _, at most 32 characters."
  }
}

variable "ssh_public_key" {
  description = "SSH public key (the key itself, not a path) that cloud-init installs for the user."
  type        = string

  validation {
    condition     = can(regex("^(ssh-|ecdsa-|sk-)\\S+ \\S+", trimspace(var.ssh_public_key)))
    error_message = "The ssh_public_key must be a public key in OpenSSH format, e.g. \"ssh-ed25519 AAAA... comment\"."
  }
}
