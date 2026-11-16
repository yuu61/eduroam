locals {
  prefixlen = split("/", var.network_cidr)[1]

  containers = {
    for key, spec in var.containers : key => merge(spec, {
      hostname = "${var.name_prefix}-${key}"
      ipv4     = cidrhost(var.network_cidr, spec.host_number)
    })
  }

  inventory_groups = distinct(flatten([for ct in local.containers : ct.groups]))

  inventory = {
    all = {
      vars = {
        ansible_user            = "root"
        ansible_ssh_common_args = "-o StrictHostKeyChecking=accept-new"
        lab_network_cidr        = var.network_cidr
      }
      children = {
        for group in local.inventory_groups : group => {
          hosts = {
            for ct in local.containers : ct.hostname => {
              ansible_host = ct.ipv4
              service_ipv4 = ct.ipv4
            }
            if contains(ct.groups, group)
          }
        }
      }
    }
  }
}

resource "proxmox_virtual_environment_container" "this" {
  for_each = local.containers

  node_name     = var.node_name
  vm_id         = each.value.vm_id
  description   = "eduroam: ${join(", ", each.value.groups)} (managed by OpenTofu)"
  tags          = concat(["eduroam"], each.value.groups)
  unprivileged  = true
  start_on_boot = true
  started       = true

  # Debian 13 の systemd を非特権コンテナで動かすために必要
  features {
    nesting = true
  }

  operating_system {
    template_file_id = var.template_file_id
    type             = "debian"
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory_mb
  }

  disk {
    datastore_id = var.datastore_id
    size         = each.value.disk_gb
  }

  network_interface {
    name    = "eth0"
    bridge  = var.bridge
    vlan_id = var.vlan_id
  }

  initialization {
    hostname = each.value.hostname

    ip_config {
      ipv4 {
        address = "${each.value.ipv4}/${local.prefixlen}"
        gateway = var.gateway
      }
    }

    dns {
      servers = var.dns_servers
    }

    user_account {
      keys = [trimspace(file(pathexpand(var.ssh_public_key_file)))]
    }
  }
}

resource "local_file" "inventory" {
  filename        = coalesce(var.inventory_path, "${path.module}/../../../ansible/inventories/proxmox/hosts.yml")
  file_permission = "0644"
  content         = "# OpenTofu (tofu/envs/proxmox) が生成する。手で編集しない\n${yamlencode(local.inventory)}"

  depends_on = [proxmox_virtual_environment_container.this]
}
