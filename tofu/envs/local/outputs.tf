output "instances" {
  description = "作成したコンテナと IPv4 アドレス"
  value       = { for key, inst in local.instances : inst.name => inst.ipv4 }
}

output "inventory_path" {
  description = "生成した Ansible inventory"
  value       = local_file.inventory.filename
}
