# eduroam RADIUS 環境（OpenTofu + Ansible）
# Linux / WSL2 上で実行する。ENV_NAME で環境を選ぶ（local: Incus / proxmox: Proxmox VE）

ENV_NAME ?= local

TOFU_DIR    := tofu/envs/$(ENV_NAME)
INV_DIR     := ansible/inventories/$(ENV_NAME)
INVENTORY   := $(INV_DIR)/hosts.yml
VAULT_FILE  := $(INV_DIR)/group_vars/all/vault.yml
SECRETS_DIR ?= $(HOME)/.local/share/eduroam/$(ENV_NAME)

# /mnt/c 配下（ワールド書き込み可能）でも ansible.cfg を確実に読ませる
export ANSIBLE_CONFIG := $(CURDIR)/ansible/ansible.cfg
export EDUROAM_SECRETS_DIR := $(SECRETS_DIR)

PLAYBOOK := ansible-playbook -i $(INVENTORY) $(ANSIBLE_ARGS)
# local は使い捨てのため承認なしで apply する
TOFU_APPLY_ARGS ?= $(if $(filter local,$(ENV_NAME)),-auto-approve,)

# local 環境のコンテナ名
RADIUS_INSTANCE ?= eduroam-radius
LDAP_INSTANCE   ?= eduroam-ldap

.PHONY: help incus-host setup infra plan deploy up test down logs radius-debug ldap-search lint clean-pki

help:
	@echo "使い方: make <target> [ENV_NAME=local|proxmox]"
	@echo "  incus-host    ホストに Incus を導入（local の初回のみ・sudo）"
	@echo "  setup         Ansible コレクション導入、vault.yml 作成、tofu init"
	@echo "  plan          tofu plan"
	@echo "  infra         tofu apply（コンテナ作成と inventory 生成）"
	@echo "  deploy        Ansible で構成（設定変更の反映もこれ）"
	@echo "  up            infra + deploy"
	@echo "  test          認証テスト（radtest / eapol_test）"
	@echo "  down          tofu destroy"
	@echo "  logs          FreeRADIUS のログ（local）"
	@echo "  radius-debug  FreeRADIUS をデバッグモード（-X）で前面実行（local）"
	@echo "  ldap-search   検証用 OpenLDAP のエントリ表示（local）"
	@echo "  lint          構文チェック（ansible / tofu）"
	@echo "  clean-pki     検証用 PKI を削除（次回 deploy で再生成）"

incus-host:
	sudo bash scripts/incus-host-setup.sh

setup:
	ansible-galaxy collection install -r ansible/requirements.yml
	@if [ ! -f $(VAULT_FILE) ]; then \
		cp $(INV_DIR)/vault.yml.example $(VAULT_FILE); \
		echo "$(VAULT_FILE) を作成しました。シークレットを変更してください。"; \
	fi
	tofu -chdir=$(TOFU_DIR) init

plan:
	tofu -chdir=$(TOFU_DIR) plan

infra:
	tofu -chdir=$(TOFU_DIR) apply $(TOFU_APPLY_ARGS)

deploy:
	$(PLAYBOOK) ansible/playbooks/site.yml

up: infra deploy

test:
	$(PLAYBOOK) ansible/playbooks/test.yml

down:
	tofu -chdir=$(TOFU_DIR) destroy $(TOFU_APPLY_ARGS)

logs:
	incus exec $(RADIUS_INSTANCE) -- journalctl -u freeradius -f

# Ctrl+C で終了すると通常のサービスとして再起動する
radius-debug:
	incus exec $(RADIUS_INSTANCE) -- systemctl stop freeradius
	-incus exec -t $(RADIUS_INSTANCE) -- systemd-run --quiet --pty --collect \
		-p EnvironmentFile=/etc/freeradius/eduroam.env /usr/sbin/freeradius -X
	incus exec $(RADIUS_INSTANCE) -- systemctl start freeradius

ldap-search:
	incus exec $(LDAP_INSTANCE) -- ldapsearch -LLL -Q -H ldapi:/// -Y EXTERNAL -b dc=kobedenshi,dc=ac,dc=jp

lint:
	ansible-playbook -i $(INVENTORY) --syntax-check ansible/playbooks/site.yml ansible/playbooks/test.yml
	tofu -chdir=$(TOFU_DIR) fmt -check
	tofu -chdir=$(TOFU_DIR) validate

clean-pki:
	rm -rf $(SECRETS_DIR)/pki
