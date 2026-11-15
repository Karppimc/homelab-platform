output "name" {
  description = "Name of the VM."
  value       = proxmox_virtual_environment_vm.this.name
}

output "vm_id" {
  description = "Proxmox VM ID of the node."
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "ipv4_address" {
  description = "Static IPv4 address of the VM, without a prefix length."
  value       = var.ip
}
