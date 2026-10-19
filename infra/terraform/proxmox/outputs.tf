output "k3s_nodes" {
  value = { for name, node in var.k3s_nodes : name => node.ip }
}