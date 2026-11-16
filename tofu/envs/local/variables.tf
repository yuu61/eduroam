variable "name_prefix" {
  description = "インスタンス名の接頭辞"
  type        = string
  default     = "eduroam"
}

variable "network_name" {
  description = "検証用ブリッジ名（15文字以内）"
  type        = string
  default     = "eduroambr0"
}

variable "network_cidr" {
  description = "検証用ネットワーク。先頭アドレスがゲートウェイ兼 DNS になる"
  type        = string
  default     = "10.180.0.0/24"
}

variable "image" {
  description = "インスタンスのイメージ（cloud-init 対応版を使う）"
  type        = string
  default     = "images:debian/13/cloud"
}

variable "storage_pool" {
  description = "ルートディスクを置く Incus ストレージプール"
  type        = string
  default     = "default"
}

variable "instances" {
  description = "作成するコンテナ。host_number はネットワーク内のホスト番号、groups は Ansible のグループ"
  type = map(object({
    host_number = number
    groups      = list(string)
  }))
  default = {
    radius = { host_number = 10, groups = ["radius"] }
    ldap   = { host_number = 11, groups = ["ldap_test"] }
    client = { host_number = 12, groups = ["test_client"] }
  }
}

variable "inventory_path" {
  description = "生成する Ansible inventory のパス"
  type        = string
  default     = null
}
