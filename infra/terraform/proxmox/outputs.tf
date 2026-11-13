output "k3s_nodes" {
  description = "Static IPv4 address of each k3s node, keyed by VM name."
  value       = { for name, node in var.k3s_nodes : name => node.ip }
}
