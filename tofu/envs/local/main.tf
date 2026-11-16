locals {
  gateway   = cidrhost(var.network_cidr, 1)
  prefixlen = split("/", var.network_cidr)[1]

  instances = {
    for key, spec in var.instances : key => {
      name   = "${var.name_prefix}-${key}"
      ipv4   = cidrhost(var.network_cidr, spec.host_number)
      groups = spec.groups
    }
  }

  inventory_groups = distinct(flatten([for inst in local.instances : inst.groups]))

  inventory = {
    all = {
      vars = {
        ansible_connection = "community.general.incus"
        lab_network_cidr   = var.network_cidr
      }
      children = {
        for group in local.inventory_groups : group => {
          hosts = {
            for inst in local.instances : inst.name => { service_ipv4 = inst.ipv4 }
            if contains(inst.groups, group)
          }
        }
      }
    }
  }
}

# DHCP は使わず、各コンテナに cloud-init で固定 IP を設定する
# （WSL2 の mirrored ネットワークでは Windows 側が UDP/67 を使用しているため）
resource "incus_network" "lab" {
  name        = var.network_name
  description = "eduroam lab network (managed by OpenTofu)"

  config = {
    "ipv4.address" = "${local.gateway}/${local.prefixlen}"
    "ipv4.nat"     = "true"
    "ipv4.dhcp"    = "false"
    "ipv6.address" = "none"
  }
}

resource "incus_instance" "this" {
  for_each = local.instances

  name        = each.value.name
  description = "eduroam lab: ${join(", ", each.value.groups)} (managed by OpenTofu)"
  image       = var.image
  type        = "container"

  config = {
    "cloud-init.network-config" = yamlencode({
      version = 2
      ethernets = {
        eth0 = {
          addresses   = ["${each.value.ipv4}/${local.prefixlen}"]
          routes      = [{ to = "0.0.0.0/0", via = local.gateway }]
          nameservers = { addresses = [local.gateway] }
        }
      }
    })
  }

  device {
    name = "root"
    type = "disk"
    properties = {
      pool = var.storage_pool
      path = "/"
    }
  }

  device {
    name = "eth0"
    type = "nic"
    properties = {
      network = incus_network.lab.name
    }
  }

  wait_for {
    type = "ipv4"
  }
}

resource "local_file" "inventory" {
  filename        = coalesce(var.inventory_path, "${path.module}/../../../ansible/inventories/local/hosts.yml")
  file_permission = "0644"
  content         = "# OpenTofu (tofu/envs/local) が生成する。手で編集しない\n${yamlencode(local.inventory)}"

  depends_on = [incus_instance.this]
}
