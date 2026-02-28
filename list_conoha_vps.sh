#!/bin/bash

# =========================================================
# ConoHa VPS Instance Listing Script
# =========================================================

# --- Load Configuration from .env ---
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "エラー: .env ファイルが見つかりません。"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "エラー: JSON解析ツール 'jq' がインストールされていません。"
    exit 1
fi

# --- Parse Arguments ---
DEBUG=0
for arg in "$@"; do
    if [ "$arg" == "-d" ] || [ "$arg" == "--debug" ]; then
        DEBUG=1
    fi
done

IDENTITY_API="https://identity.${REGION}.conoha.io/v2.0"
COMPUTE_API="https://compute.${REGION}.conoha.io/v2/${TENANT_ID}"

echo "[*] 認証トークンを取得しています..."
AUTH_URL="${IDENTITY_API}/tokens"
PAYLOAD_FILE="list_auth_payload.json"
jq -n \
  --arg username "$API_USER" \
  --arg password "$API_PASSWORD" \
  --arg tenantId "$TENANT_ID" \
  '{"auth":{"passwordCredentials":{"username":$username,"password":$password},"tenantId":$tenantId}}' > "$PAYLOAD_FILE"

TOKEN_RES=$(curl -s -X POST -H "Accept: application/json" -H "Content-Type: application/json" -d @$PAYLOAD_FILE $AUTH_URL)
rm -f "$PAYLOAD_FILE"

TOKEN=$(echo "$TOKEN_RES" | jq -r '.access.token.id // empty')

if [ -z "$TOKEN" ]; then
    echo " -> エラー: 認証に失敗しました。"
    exit 1
fi

echo "[*] インスタンス一覧を取得しています..."
LIST_URL="${COMPUTE_API}/servers/detail"
LIST_RES=$(curl -s -X GET -H "Accept: application/json" -H "X-Auth-Token: ${TOKEN}" ${LIST_URL})

if [ $DEBUG -eq 1 ]; then
    echo "------------------------------------------------------------------------------------------------"
    echo " DEBUG: RAW JSON RESPONSE"
    echo "------------------------------------------------------------------------------------------------"
    echo "$LIST_RES" | jq .
    echo "------------------------------------------------------------------------------------------------"
    echo ""
fi

# 結果の表示
echo "------------------------------------------------------------------------------------------------"
printf "%-25s | %-36s | %-10s | %s\n" "Name Tag" "Instance ID" "Status" "IP Address"
echo "------------------------------------------------------------------------------------------------"

# jqを使用してサーバー情報を抽出し、整形して表示
# ネームタグは .metadata.instance_name_tag に格納されています
echo "$LIST_RES" | jq -r '.servers[] | "\(.metadata.instance_name_tag // .name)|\(.id)|\(.status)|\(.addresses[][] | select(.version == 4) | .addr // "N/A")"' | while IFS='|' read -r name id status ip; do
    printf "%-25s | %-36s | %-10s | %s\n" "$name" "$id" "$status" "$ip"
done

echo "------------------------------------------------------------------------------------------------"
echo ""
echo "インスタンスを削除する場合:"
echo "./delete_conoha_vps.sh [INSTANCE_ID]"
