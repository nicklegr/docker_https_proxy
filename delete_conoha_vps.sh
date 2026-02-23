#!/bin/bash

# =========================================================
# ConoHa VPS Instance Deletion Script
# =========================================================

# --- Load Configuration from .env ---
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "エラー: .env ファイルが見つかりません。"
    exit 1
fi

if [ -z "$1" ]; then
    echo "使用方法: $0 [INSTANCE_ID]"
    exit 1
fi

INSTANCE_ID=$1

if ! command -v jq &> /dev/null; then
    echo "エラー: 'jq' が必要です。"
    exit 1
fi

IDENTITY_API="https://identity.${REGION}.conoha.io/v2.0"
COMPUTE_API="https://compute.${REGION}.conoha.io/v2/${TENANT_ID}"

echo "[*] 認証トークンを取得しています..."
AUTH_URL="${IDENTITY_API}/tokens"
PAYLOAD_FILE="del_auth_payload.json"
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

echo "[*] インスタンス (ID: $INSTANCE_ID) を削除しています..."
DELETE_URL="${COMPUTE_API}/servers/${INSTANCE_ID}"
RES=$(curl -s -w "%{http_code}" -o /dev/null -X DELETE -H "X-Auth-Token: ${TOKEN}" ${DELETE_URL})

if [ "$RES" == "204" ]; then
    echo " -> 成功: インスタンスの削除リクエストが受け付けられました。"
else
    echo " -> エラー: インスタンスの削除に失敗しました。ステータスコード: $RES"
    exit 1
fi
