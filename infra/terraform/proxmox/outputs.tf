output "test_vm_ip" {
  value = proxmox_virtual_environment_vm.test.ipv4_addresses[1][0]
}