variable "proxmox_endpoint" {
  type    = string
  default = "https://192.168.1.50:8006/"
}

variable "proxmox_api_token" {
  type      = string
  sensitive = true
}

variable "node_name" {
  type    = string
  default = "pve"
}

variable "template_id" {
  type    = number
  default = 9000
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_ed25519.pub"
}

variable "gateway" {
  type    = string
  default = "192.168.1.1"
}

variable "k3s_nodes" {
  description = "k3s-klusterin koneet. Lisää tai poista rivi muuttaaksesi klusteria."
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
    "k3s-worker-1" = { vm_id = 211, role = "worker",        ip = "192.168.1.231", cores = 3, memory = 4096, disk = 50 }
    "k3s-worker-2" = { vm_id = 212, role = "worker",        ip = "192.168.1.232", cores = 3, memory = 4096, disk = 50 }
  }
}