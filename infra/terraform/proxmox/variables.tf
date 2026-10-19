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