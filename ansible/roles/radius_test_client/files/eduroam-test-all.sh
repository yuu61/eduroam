#!/bin/bash
# eduroam 認証テスト一括実行スクリプト（Ansible role: radius_test_client が配置）
# 設定は /etc/eduroam-test/ から読み込む。1件でも失敗すると終了コード 1 を返す

set -u

ENV_FILE="${ENV_FILE:-/etc/eduroam-test/test.env}"

# KEY=VALUE 形式の設定を読み込む（シェルとして評価しない）
while IFS= read -r line; do
    case "${line}" in
        RADIUS_SERVER=*) RADIUS_SERVER="${line#*=}" ;;
        RADIUS_SECRET=*) RADIUS_SECRET="${line#*=}" ;;
        TEST_USER=*) TEST_USER="${line#*=}" ;;
        TEST_PASSWORD=*) TEST_PASSWORD="${line#*=}" ;;
        CONF_DIR=*) CONF_DIR="${line#*=}" ;;
        *) ;;
    esac
done <"${ENV_FILE}"

: "${RADIUS_SERVER:?}" "${RADIUS_SECRET:?}" "${TEST_USER:?}" "${TEST_PASSWORD:?}" "${CONF_DIR:?}"

failures=0

# check <説明> <期待する出力の正規表現> <コマンド...>
check() {
    local description="$1" pattern="$2"
    shift 2
    echo "--- ${description} ---"
    local output
    output="$("$@" 2>&1)"
    if grep -qE "${pattern}" <<<"${output}"; then
        echo "結果: PASS"
    else
        echo "結果: FAIL（期待: ${pattern}）"
        tail -n 5 <<<"${output}"
        failures=$((failures + 1))
    fi
    echo ""
}

eapol() {
    eapol_test -c "${CONF_DIR}/$1" -s "${RADIUS_SECRET}" -a "${RADIUS_SERVER}"
}

echo "========================================"
echo " eduroam 認証テスト (RADIUS: ${RADIUS_SERVER}, ユーザー: ${TEST_USER})"
echo "========================================"
echo ""

check "テスト1: EAP なしの PAP は拒否される（radtest）" \
    "Received Access-Reject" \
    radtest "${TEST_USER}" "${TEST_PASSWORD}" "${RADIUS_SERVER}" 0 "${RADIUS_SECRET}"

check "テスト2: EAP-TTLS/PAP で受理される（eapol_test）" \
    "^SUCCESS$" \
    eapol eapol_test.conf

check "テスト3: EAP-TTLS/PAP 不正パスワードは拒否される（eapol_test）" \
    "EAP: Received EAP-Failure" \
    eapol eapol_test-wrong-password.conf

check "テスト4: 自機関以外の realm の内部 Identity は拒否される（eapol_test）" \
    "EAP: Received EAP-Failure" \
    eapol eapol_test-foreign-realm.conf

echo "========================================"
if [[ ${failures} -eq 0 ]]; then
    echo " 全テスト PASS"
else
    echo " FAIL: ${failures} 件"
fi
echo "========================================"

[[ ${failures} -eq 0 ]]
