resource "proxmox_virtual_environment_vm" "k3s" {
  for_each = var.k3s_nodes

  name      = each.key
  vm_id     = each.value.vm_id
  node_name = var.node_name
  tags      = ["terraform", "k3s", each.value.role]
  on_boot   = true

  clone {
    vm_id = var.template_id
  }

  agent {
    enabled = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = each.value.disk
    discard      = "on"
    ssd          = true
  }

  initialization {
    datastore_id = var.datastore_id
    ip_config {
      ipv4 {
        address = "${each.value.ip}/${var.network_prefix_length}"
        gateway = var.gateway
      }
    }
    dns {
      servers = [var.gateway]
    }
    user_account {
      username = var.vm_username
      keys     = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }
  }

  stop_on_destroy = true
}
