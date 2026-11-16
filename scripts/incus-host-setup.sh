#!/usr/bin/env bash
# ローカル検証環境（tofu/envs/local）のホスト準備: Incus の導入と初期化
# 対象: Debian/Ubuntu（WSL2 を含む）。root で実行する（make incus-host は sudo 経由で呼ぶ）

set -euo pipefail

LAB_BRIDGE="${LAB_BRIDGE:-eduroambr0}"
STORAGE_POOL="${STORAGE_POOL:-default}"
TARGET_USER="${SUDO_USER:-${USER}}"

if [[ ${EUID} -ne 0 ]]; then
    echo "root で実行してください（例: sudo $0）" >&2
    exit 1
fi

# 1. Incus の導入
if ! command -v incus >/dev/null 2>&1; then
    echo "--- Incus をインストール ---"
    apt-get update -q
    DEBIAN_FRONTEND=noninteractive apt-get install -y -q incus
fi
systemctl enable --now incus.socket >/dev/null 2>&1 || true

# 2. ストレージプール（incus admin init --minimal は DHCP 付きの incusbr0 も作るため使わない）
if ! incus storage show "${STORAGE_POOL}" >/dev/null 2>&1; then
    echo "--- ストレージプール ${STORAGE_POOL} を作成 ---"
    incus storage create "${STORAGE_POOL}" dir
fi

# 3. 実行ユーザーを incus-admin グループに追加
if [[ ${TARGET_USER} != "root" ]] && ! id -nG "${TARGET_USER}" | tr ' ' '\n' | grep -qx incus-admin; then
    echo "--- ${TARGET_USER} を incus-admin グループに追加 ---"
    usermod -aG incus-admin "${TARGET_USER}"
    echo "グループ変更は新しいログインセッションから有効になります（WSL は wsl --terminate <distro> で再起動）。"
fi

# 4. Docker が FORWARD を DROP にしている環境では、検証用ブリッジの転送を許可する
if command -v iptables >/dev/null 2>&1 && iptables -S DOCKER-USER >/dev/null 2>&1; then
    echo "--- Docker の FORWARD 制限を ${LAB_BRIDGE} について解除（systemd ユニット） ---"
    cat >/etc/systemd/system/eduroam-lab-forward.service <<EOF
[Unit]
Description=Allow forwarding for the eduroam lab bridge (${LAB_BRIDGE}) past Docker's FORWARD policy
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/sh -c 'iptables -C DOCKER-USER -i ${LAB_BRIDGE} -j ACCEPT 2>/dev/null || iptables -I DOCKER-USER -i ${LAB_BRIDGE} -j ACCEPT'
ExecStart=/bin/sh -c 'iptables -C DOCKER-USER -o ${LAB_BRIDGE} -j ACCEPT 2>/dev/null || iptables -I DOCKER-USER -o ${LAB_BRIDGE} -j ACCEPT'
ExecStop=-/sbin/iptables -D DOCKER-USER -i ${LAB_BRIDGE} -j ACCEPT
ExecStop=-/sbin/iptables -D DOCKER-USER -o ${LAB_BRIDGE} -j ACCEPT

[Install]
WantedBy=docker.service
EOF
    systemctl daemon-reload
    systemctl enable eduroam-lab-forward.service >/dev/null
    systemctl restart eduroam-lab-forward.service
fi

echo "=== Incus の準備が完了しました ==="
incus version
