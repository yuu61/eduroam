output "containers" {
  description = "作成した LXC と IPv4 アドレス"
  value       = { for key, ct in local.containers : ct.hostname => ct.ipv4 }
}

output "inventory_path" {
  description = "生成した Ansible inventory"
  value       = local_file.inventory.filename
}
