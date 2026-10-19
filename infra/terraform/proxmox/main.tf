resource "proxmox_virtual_environment_vm" "test" {
  name      = "test-vm"
  node_name = var.node_name
  tags      = ["terraform", "test"]

  clone {
    vm_id = var.template_id
  }

  agent {
    enabled = true
  }

  cpu {
    cores = 2
    type  = "host"
  }

  memory {
    dedicated = 2048
  }

  disk {
    datastore_id = "local-lvm"
    interface    = "scsi0"
    size         = 20
    discard      = "on"
    ssd          = true
  }

  initialization {
    datastore_id = "local-lvm"
    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }
    user_account {
      username = "santeri"
      keys     = [trimspace(file(pathexpand(var.ssh_public_key_path)))]
    }
  }

  stop_on_destroy = true
}