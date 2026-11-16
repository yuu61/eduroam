variable "proxmox_endpoint" {
  description = "Proxmox VE API の URL（例: https://pve.example.ac.jp:8006/）"
  type        = string
}

variable "proxmox_insecure" {
  description = "API の TLS 証明書検証を省略する（自己署名証明書の PVE 用）"
  type        = bool
  default     = false
}

variable "node_name" {
  description = "LXC を作成する Proxmox VE ノード名"
  type        = string
}

variable "template_file_id" {
  description = "LXC テンプレート（例: local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst）"
  type        = string
}

variable "datastore_id" {
  description = "ルートディスクを置くストレージ"
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "接続するブリッジ"
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "VLAN ID（VLAN-aware ブリッジを使わない場合は null）"
  type        = number
  default     = null
}

variable "network_cidr" {
  description = "コンテナを置くネットワーク（RADIUS クライアント定義にも使う）"
  type        = string
}

variable "gateway" {
  description = "デフォルトゲートウェイ"
  type        = string
}

variable "dns_servers" {
  description = "DNS サーバ"
  type        = list(string)
}

variable "ssh_public_key_file" {
  description = "root に登録する SSH 公開鍵（Ansible の接続に使う）"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}

variable "name_prefix" {
  description = "ホスト名の接頭辞"
  type        = string
  default     = "eduroam"
}

variable "containers" {
  description = "作成する LXC。host_number はネットワーク内のホスト番号、groups は Ansible のグループ"
  type = map(object({
    vm_id       = number
    host_number = number
    groups      = list(string)
    cores       = optional(number, 1)
    memory_mb   = optional(number, 1024)
    disk_gb     = optional(number, 8)
  }))
}

variable "inventory_path" {
  description = "生成する Ansible inventory のパス"
  type        = string
  default     = null
}
