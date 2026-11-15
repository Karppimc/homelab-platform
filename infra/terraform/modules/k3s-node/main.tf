# k3s-node: Creates one k3s node as a Proxmox VM cloned from a cloud-init template.
#
# No provider block here: the calling configuration configures the provider.

resource "proxmox_virtual_environment_vm" "this" {
  name      = var.name
  vm_id     = var.vm_id
  node_name = var.node_name
  tags      = ["terraform", "k3s", var.role]
  on_boot   = true

  clone {
    vm_id = var.template_id
  }

  agent {
    enabled = true
  }

  cpu {
    cores = var.cores
    type  = "host"
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = var.disk
    discard      = "on"
    ssd          = true
  }

  initialization {
    datastore_id = var.datastore_id
    ip_config {
      ipv4 {
        address = "${var.ip}/${var.network_prefix_length}"
        gateway = var.gateway
      }
    }
    dns {
      servers = var.dns_servers
    }
    user_account {
      username = var.username
      keys     = [trimspace(var.ssh_public_key)]
    }
  }

  stop_on_destroy = true
}
