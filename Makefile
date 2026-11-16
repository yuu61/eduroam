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

# リンター／フォーマッター。uvx で版を固定して実行する（CI も同じ版を使う）
UVX ?= uvx
ANSIBLE_LINT_VERSION := 26.11.0
# shellcheck-py 0.11.0.1 = ShellCheck 0.11.0
SHELLCHECK_PY_VERSION := 0.11.0.1
# shfmt-py 4.2.0 = shfmt 3.14.1（書式は .editorconfig に従う）
SHFMT_PY_VERSION := 4.2.0
YAMLLINT_VERSION := 1.38.0
# ansible-core は実行環境（Ubuntu 24.04 の apt 版 2.16）に合わせる。yamllint は単体実行と同じ版にする
ANSIBLE_LINT := $(UVX) --python 3.12 --from ansible-lint==$(ANSIBLE_LINT_VERSION) --with 'ansible-core>=2.16,<2.17' --with yamllint==$(YAMLLINT_VERSION) ansible-lint
YAMLLINT     := $(UVX) yamllint==$(YAMLLINT_VERSION)
SHELLCHECK   := $(UVX) --from shellcheck-py==$(SHELLCHECK_PY_VERSION) shellcheck
SHFMT        := $(UVX) --from shfmt-py==$(SHFMT_PY_VERSION) shfmt
SH_FILES      = $(shell git ls-files '*.sh')
TOFU_ENVS     = $(wildcard tofu/envs/*)

.PHONY: help incus-host setup infra plan deploy up test down logs radius-debug ldap-search lint lint-yaml lint-ansible lint-shell lint-tofu fmt clean-pki

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
	@echo "  lint          リンター（yamllint / ansible-lint / shellcheck / shfmt / tofu fmt・validate、全環境）"
	@echo "                個別: lint-yaml / lint-ansible / lint-shell / lint-tofu"
	@echo "  fmt           フォーマッター（ansible-lint --fix / shfmt / tofu fmt）"
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

# make -k lint で全ツールの結果をまとめて表示できる
lint: lint-yaml lint-ansible lint-shell lint-tofu

# ansible-lint は一部のファイル（.github/workflows など）で yamllint の指摘を除外するため、単体でも実行する
lint-yaml:
	$(YAMLLINT) --strict .

# ansible-lint はプレイブックの構文チェック（--syntax-check）も行う。
# コレクションは導入済みのもの（make setup）を使う
lint-ansible:
	$(ANSIBLE_LINT)

lint-shell:
	$(SHELLCHECK) $(SH_FILES)
	$(SHFMT) -d $(SH_FILES)

lint-tofu:
	tofu fmt -check -diff -recursive tofu
	@set -e; for d in $(TOFU_ENVS); do \
		echo "tofu validate: $$d"; \
		tofu -chdir=$$d init -backend=false -input=false >/dev/null; \
		tofu -chdir=$$d validate; \
	done

fmt:
	$(ANSIBLE_LINT) --fix
	$(SHFMT) -w $(SH_FILES)
	tofu fmt -recursive tofu

clean-pki:
	rm -rf $(SECRETS_DIR)/pki
