# CLAUDE.md

## プロジェクト概要

学校法人コンピュータ総合学園（神戸電子専門学校・神戸情報大学院大学）へのeduroam導入に向けた技術検証環境。
FreeRADIUS + Google Workspace Secure LDAP による EAP-TTLS/PAP 認証を、OpenTofu（ホスト作成）と Ansible（構成管理）で構築する。Docker には依存しない。

## 技術スタック

- **RADIUS**: FreeRADIUS 3.2.7（Debian 13 パッケージ）
- **LDAP**: OpenLDAP slapd（Phase 1テスト用、Debian パッケージ）、Google Workspace Secure LDAP（Phase 2本番）
- **認証方式**: EAP-TTLS/PAP（Google WorkspaceがNTハッシュ非対応のため唯一の選択肢）
- **ホスト作成**: OpenTofu（`lxc/incus` provider でローカル Incus、`bpg/proxmox` provider で Proxmox VE LXC）
- **構成管理**: Ansible（ansible-core 2.16+、community.general / community.crypto）
- **OS**: Debian 13（全ホスト共通）

## ディレクトリ構造

```
tofu/envs/
  local/                        # Incus（WSL2/Linux）に radius/ldap/client の3コンテナを作成
  proxmox/                      # Proxmox VE に LXC を作成（terraform.tfvars.example をコピーして使用）
ansible/
  ansible.cfg                   # Makefile が ANSIBLE_CONFIG で指定する
  requirements.yml              # Ansible コレクション
  playbooks/
    site.yml                    # 構成（bootstrap → lab_pki → openldap_test → freeradius → test client）
    test.yml                    # 認証テスト
  inventories/<環境>/
    hosts.yml                   # OpenTofu が生成（git-ignored）
    vault.yml.example           # シークレットのテンプレート
    group_vars/all/main.yml     # 環境ごとの変数（Phase 切替もここ）
    group_vars/all/vault.yml    # シークレット（git-ignored）
  roles/
    freeradius/                 # FreeRADIUS 構成
      templates/                # clients.conf / proxy.conf / mods-available/{eap,ldap,ldap_google} / sites-available/eduroam-inner-tunnel
      files/sites-available/eduroam  # 外部EAPトンネル
    openldap_test/              # 検証用 slapd とテストユーザー
    radius_test_client/         # radtest / eapol_test とテストスクリプト（eduroam-test-all）
    lab_pki/                    # 検証用 CA・サーバ証明書をコントローラに生成
scripts/
  incus-host-setup.sh           # Incus の導入・初期化（make incus-host）
docs/                           # 技術ドキュメント
  application/                  # eduroam JP 申請手続き
  infrastructure/               # インフラ・技術設計
    architecture.md             # システム構成設計
    deployment-strategy.md      # 拠点別展開戦略（財務分析・L8リスク含む）
    freeradius3-setup.md        # FreeRADIUS設定リファレンス
    google-secure-ldap-802.1x-feasibility.md  # Google LDAP実現性調査
    virtualization-comparison.md # 仮想化基盤比較
  ap/                           # アクセスポイント調査
    existing-ap-survey.md       # 既存AP棚卸し調査結果
    vendor-survey.md            # ベンダー比較概要
    vendors/                    # ベンダー別詳細評価
      aruba-hpe.md / cisco-catalyst-meraki.md / juniper-mist.md / ubiquiti-unifi.md
  UPKI/                         # NII UPKI証明書関連ドキュメント
plans/                          # 実装計画
```

## よく使うコマンド

Linux / WSL2（systemd 有効）で実行する。Ansible・OpenTofu は Windows ネイティブでは動かさない。
`ENV_NAME=proxmox` で Proxmox 環境を操作する（既定は `local`）。

```bash
make incus-host     # Incus の導入（local の初回のみ、sudo）
make setup          # Ansible コレクション導入 + vault.yml 作成 + tofu init
make plan           # tofu plan
make infra          # tofu apply（ホスト作成 + inventory 生成）
make deploy         # Ansible で構成（設定変更の反映）
make up             # infra + deploy
make test           # 認証テスト（4項目）
make down           # tofu destroy
make logs           # FreeRADIUSログ表示（local）
make radius-debug   # FreeRADIUS を -X で前面実行（local、Ctrl+C で通常起動に戻る）
make ldap-search    # 検証用 OpenLDAP のエントリ表示（local）
make lint           # ansible-playbook --syntax-check + tofu fmt -check / validate
make clean-pki      # 検証用 PKI 削除
```

## 設定変更時のワークフロー

FreeRADIUS の設定は `ansible/roles/freeradius/` のテンプレートが正。対象ホストの `/etc/freeradius/3.0/` を直接編集しない。
変更後は `make deploy` で反映する。変更があったときだけハンドラが `freeradius -Cx` で設定を検証し、通った場合のみ再起動する。
`make deploy` は冪等で、変更がなければ `changed=0` になる。

ホスト構成（台数・IP・イメージ）を変える場合は `tofu/envs/<環境>/` を編集して `make infra`。

## テスト用認証情報

`ansible/inventories/<環境>/group_vars/all/vault.yml` で管理（git-ignored）。`make setup` が `vault.yml.example` からコピーする。

| 項目 | 変数 | 備考 |
|------|------|------|
| RADIUS shared secret | `vault_radius_secret` | FreeRADIUS へは `RADIUS_SECRET` |
| LDAP admin password | `vault_ldap_admin_password` | FreeRADIUS へは `LDAP_BIND_PASSWORD` |
| テストユーザーのパスワード | `vault_test_user_passwords` | `testuser1` / `testuser2` |

LDAP組織名（`Kobe Denshi`）、ドメイン（`kobedenshi.ac.jp`）、Base DN（`dc=kobedenshi,dc=ac,dc=jp`）、テストユーザー（`testuser1@kobedenshi.ac.jp`）は `group_vars/all/main.yml` に記載する。

Phase 2以降で追加する値（`inventories/proxmox/vault.yml.example`にコメントアウトで記載済み）:
- **Phase 2**: `vault_google_ldap_user`, `vault_google_ldap_password`（FreeRADIUS へは `GOOGLE_LDAP_USER` / `GOOGLE_LDAP_PASS`）。クライアント証明書・鍵は `freeradius_google_ldap_cert_src` / `_key_src` で指定
- **Phase 4**: `vault_flr_secret`（`freeradius_secret_env` に `FLR_SECRET` として追加）

## FreeRADIUS設定の注意事項

- Debian パッケージのレイアウト: 設定 `/etc/freeradius/3.0/`、バイナリ `freeradius`、ユーザー `freerad`。LDAP モジュールは `freeradius-ldap` パッケージ。
- ストックの`radiusd.conf`を使用（カスタム版は持たない）。標準モジュール（pap, suffix, attr_filter, linelog等）はパッケージのものをそのまま利用。ストックの `default` / `inner-tunnel` サイトはロールが無効化する。
- `mods-enabled/`と`sites-enabled/`のシンボリックリンクは freeradius ロールが管理する。
- **Phase切替**は `group_vars/all/main.yml` の `freeradius_ldap_backend` を `openldap` → `google` に変える。有効化するモジュール（`ldap` / `ldap_google`）と inner-tunnel の参照・認証方式（`google` は LDAP bind）が連動して切り替わる。
- `freeradius_ldap_auth_method`: `attribute`（userPassword を取得して PAP 照合、openldap の既定）/ `bind`（ユーザー DN で LDAP bind）。OpenLDAP で `bind` にすると Phase 2 と同じ認証経路を検証できる。
- 内部トンネルは内部 Identity（`user@realm`）の realm を `freeradius_local_realms` と照合し、`mail` 属性で LDAP 検索する。
- FreeRADIUS v3 には `Stripped-User-Realm` 属性がない（realm は `Realm`、ユーザー部は `Stripped-User-Name`）。空の `update` セクションは起動エラーになる。
- テンプレート内で FreeRADIUS の `%{...}` を含む値を変数にする場合は `!unsafe` を付ける（Jinja2 が `{%` を解釈するため）。

## 検証フェーズ

- **Phase 1**: ローカル検証（OpenLDAP） ← 現在
- **Phase 2**: Google Workspace Secure LDAP接続
- **Phase 3**: Proxy検証（モックFLR）
- **Phase 4**: eduroam JP接続（NII登録後）
- **Phase 5**: AP統合・実機テスト

## UPKI電子証明書（本番用サーバ証明書）

eduroam本番運用ではNII UPKI電子証明書発行サービスのサーバ証明書をRADIUSサーバに使用する。

### 申請主体

- **申請機関**: 学校法人コンピュータ総合学園（利用規程 第2条第2号に該当）
- **該当根拠**: 神戸情報大学院大学（大学）を設置する学校法人であること
- **注意**: 神戸電子専門学校は専修学校であり、単独では申請資格を満たさない

### 申請に必要な体制

| 役割 | 要件 |
|------|------|
| 機関責任者 | 課長職以上または准教授相当以上の常勤教職員（1名） |
| 登録担当者 | 機関責任者から任命（複数可、証明書発行・失効の審査業務を担当） |
| 利用管理者 | 証明書の秘密鍵の管理責任者（常勤教職員） |

### 証明書の主な仕様・制約

| 項目 | 内容 |
|------|------|
| 費用 | 有償（構成員数＝常勤教員・研究者の合計で算定、学生は含まない） |
| 申請から利用開始 | **最短40日**（前々月20日までに押印済み書類が必要） |
| 有効期間 | **396日間**（指定不可、年次更新が必要） |
| 鍵長 | RSA 2048bit |
| FQDN | ドメイン申請書記載のドメインで申請（IPアドレス不可） |
| 対象ドメイン | `kobedenshi.ac.jp` と `kic.ac.jp`（法人名義で複数ドメイン管理可能） |
| 継続意思確認 | 年度ごと（2〜3月頃）。**怠ると全証明書が失効** |
| RADIUSサーバ利用 | 可能だがサポート対象外 |

### ドメイン審査方法（3択）

1. **メール認証**: `admin@`/`administrator@`/`webmaster@`/`hostmaster@`/`postmaster@<ドメイン>`のいずれかで受信
2. **DNSメール認証**: `_validation-contactemail.<ドメイン>` TXTレコードにメールアドレスを登録
3. **DNS認証**: 認証局指定のランダム値をTXTレコードに登録

### CSR作成時のDNルール

```
C  = JP（固定）
ST = Hyogo（都道府県ローマ字、機関ごとに固定）
L  = Kobe-shi（市区町村ローマ字、機関ごとに固定）
O  = 機関名英語表記（サービス参加申請時に登録）
CN = サーバのFQDN（例: radius.kobedenshi.ac.jp, radius.kic.ac.jp）
```

### 証明書発行フロー

1. 利用管理者が鍵ペア・CSRを作成
2. TSVファイルを作成し登録担当者へ送付
3. 登録担当者が本人確認後、支援システムへアップロード
4. 利用管理者に発行通知メール → 証明書取得URLからダウンロード（有効期限30日）

### 関連ドキュメント

詳細は `docs/UPKI/` 配下を参照:
- `UPKI-eduroam申請資格調査.md` — 申請主体の整理とeduroam JPへの確認事項
- `国立情報学研究所UPKI電子証明書発行サービス利用規程.md` — 利用規程全文
- `証明書申請・管理ガイド.md` — 参加申請→発行前審査→証明書管理の統合ガイド
- `サーバ証明書インストールマニュアル_OpenLDAP編.md` — OpenLDAPへの証明書インストール手順
- `UPKI証明書FAQ要約.md` — eduroam関連のFAQ要約

## 拠点別状況と展開戦略

2拠点でインフラ成熟度が大きく異なる。詳細は `docs/infrastructure/deployment-strategy.md` を参照。

| 拠点 | AP構成 | 導入難易度 | 戦略 |
|------|--------|-----------|------|
| **KIC（大学院）** | Aruba統一、WLC管理、SINET/IPv6 | 低 | SSID追加 + RADIUS統合。先行導入して実績を作る |
| **神戸電子（専門学校）** | 4社混在、37 SSID乱立、WLCなし | 高 | KIC実績をテコに法人総務トップダウンで展開 |

- **展開順序**: 2拠点同時並行が基本方針。問題発生時はKIC→神戸電子のカナリアリリースにフォールバック
- **KIC側キーパーソン**: インフラ整備した教授（Discord 1hopで連絡可能）。困ったら相談する
- **L8リスク**: 専門学校側は学科・建物ごとに管理者が異なり、ボトムアップでの合意形成が困難。法人総務からの指示でバイパスする方針

## ドキュメント記述ルール

`docs/` 配下のドキュメントは**常に最新の状態**を記述する。バージョン管理はgitに任せる。

- **禁止**: 「調査日」「作成日」「取得日」「改訂履歴」などのタイムスタンプをドキュメント内に記載しない
- **禁止**: 「以前は〜としていたが」「旧版では〜」「〜に変更した」「〜に修正」など、ドキュメント自体の変更経緯を記述しない
- **禁止**: 「調査報告」「〜を調査した」のような過去形の報告文体。現在の事実として記述する
- **許可**: 出典データの基準日（`2025年5月1日現在`等）、証拠の実施日（`nmapスキャン（2025-10-14）`等）は事実の根拠として記載してよい
- **許可**: 第三者の歴史的事実（「理化学研究所は以前〜だったが移行した」等）はそのまま記載してよい

## シークレット管理

全てのシークレット（RADIUS共有シークレット、LDAPパスワード、テストユーザーパスワード、Phase 2 以降の Google / FLR の認証情報）は `ansible/inventories/<環境>/group_vars/all/vault.yml` で管理する（`.gitignore` で除外済み）。共有・本番相当の環境では `ansible-vault encrypt` で暗号化する。

- FreeRADIUS へは systemd の EnvironmentFile（`/etc/freeradius/eduroam.env`、root 0600）で渡し、設定ファイルからは `$ENV{VAR}` 構文で参照する。設定ファイル自体にシークレットを書かない。
- 証明書・秘密鍵はリポジトリ外のコントローラ側ディレクトリ `~/.local/share/eduroam/<環境>/`（`EDUROAM_SECRETS_DIR` で変更可）に置く。検証用 PKI は `pki/` に lab_pki ロールが生成する。UPKI 証明書・Google LDAP クライアント証明書もここに置き、`freeradius_tls_*_src` / `freeradius_google_ldap_*_src` で指定する。WSL の `/mnt/c` は chmod が効かないため秘密鍵を置かない。
- OpenTofu の state（`*.tfstate`）と `terraform.tfvars` は git-ignored。Proxmox の API トークンは環境変数 `PROXMOX_VE_API_TOKEN` で渡す。

## ローカル検証環境（WSL2）の注意事項

- WSL2 の mirrored ネットワークでは Windows 側が UDP/67 を使うため、Incus ブリッジ（`eduroambr0`）は DHCP を無効にし、cloud-init で固定 IP を配る（`images:debian/13/cloud` を使う）。
- WSL 内で Docker が動いていると FORWARD ポリシーが DROP になる。`scripts/incus-host-setup.sh` が `eduroam-lab-forward.service` で `DOCKER-USER` に許可ルールを入れる。
- `/mnt/c` 配下はワールド書き込み可能なため、カレントディレクトリの `ansible.cfg` は無視される。Makefile が `ANSIBLE_CONFIG` を設定する。
- `incus-admin` グループ追加後は新しいログインセッションが必要（`wsl --terminate <distro>`）。
