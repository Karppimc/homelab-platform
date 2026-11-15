module "k3s_node" {
  source   = "../modules/k3s-node"
  for_each = var.k3s_nodes

  name  = each.key
  vm_id = each.value.vm_id
  role  = each.value.role

  node_name    = var.node_name
  datastore_id = var.datastore_id
  template_id  = var.template_id

  ip                    = each.value.ip
  network_prefix_length = var.network_prefix_length
  gateway               = var.gateway
  dns_servers           = [var.gateway]

  cores  = each.value.cores
  memory = each.value.memory
  disk   = each.value.disk

  username       = var.vm_username
  ssh_public_key = file(pathexpand(var.ssh_public_key_path))
}

# The VMs were a resource in this configuration before they became a module.
# These blocks tell Terraform that they are the same VMs, so it updates the
# state instead of destroying and recreating them. They can be removed once
# every copy of the state has been applied with them.
moved {
  from = proxmox_virtual_environment_vm.k3s["k3s-cp-1"]
  to   = module.k3s_node["k3s-cp-1"].proxmox_virtual_environment_vm.this
}

moved {
  from = proxmox_virtual_environment_vm.k3s["k3s-worker-1"]
  to   = module.k3s_node["k3s-worker-1"].proxmox_virtual_environment_vm.this
}

moved {
  from = proxmox_virtual_environment_vm.k3s["k3s-worker-2"]
  to   = module.k3s_node["k3s-worker-2"].proxmox_virtual_environment_vm.this
}
