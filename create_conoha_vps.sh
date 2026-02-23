#!/bin/bash

# =========================================================
# ConoHa VPS Instance Creation Script
# =========================================================

# --- API Configuration ---
# API情報の設定（ConoHaコントロールパネルの「API情報」から取得してください）
API_USER="your_api_username"
API_PASSWORD="your_api_password"
TENANT_ID="your_tenant_id"
REGION="tyo3" # tyo3, tyo2, tyo1, is1 のいずれかを指定

# --- VPS Configuration ---
FLAVOR_NAME="512mb" # 512MBメモリのプラン
IMAGE_NAME="centos-stream10" # CentOS Stream 10 のイメージ
ADMIN_PASSWORD="YourSecurePassword_123!" # VPSのrootパスワード（必ず強固なものに変更してください）
PROXY_PASSWORD="YourProxyPassword_123!" # HTTPSプロキシ接続用ユーザーのパスワード（必ず強固なものに変更してください）
INSTANCE_NAME="docker-https-proxy"
# =========================================================

if [ "$API_USER" == "your_api_username" ]; then
    echo "エラー: スクリプト内の API_USER などを設定してから実行してください。"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "エラー: JSON解析ツール 'jq' がインストールされていません。"
    echo "インストール方法 (Ubuntu/Debian): sudo apt install jq"
    echo "インストール方法 (Mac): brew install jq"
    exit 1
fi

IDENTITY_API="https://identity.${REGION}.conoha.io/v2.0"
COMPUTE_API="https://compute.${REGION}.conoha.io/v2/${TENANT_ID}"

echo "[*] 認証トークンを取得しています..."
TOKEN_RES=$(curl -s -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -d '{"auth":{"passwordCredentials":{"username":"'${API_USER}'","password":"'${API_PASSWORD}'"},"tenantId":"'${TENANT_ID}'"}}' \
  ${IDENTITY_API}/tokens)

TOKEN=$(echo "$TOKEN_RES" | jq -r '.access.token.id')

if [ "$TOKEN" == "null" ] || [ -z "$TOKEN" ]; then
    echo " -> エラー: トークンの取得に失敗しました。認証情報を確認してください。"
    exit 1
fi
echo " -> トークンの取得に成功しました。"

echo "[*] プラン '${FLAVOR_NAME}' の Flavor ID を取得しています..."
FLAVOR_RES=$(curl -s -X GET \
  -H "Accept: application/json" \
  -H "X-Auth-Token: ${TOKEN}" \
  ${COMPUTE_API}/flavors/detail)

FLAVOR_ID=$(echo "$FLAVOR_RES" | jq -r '.flavors[] | select(.name | ascii_downcase | contains("'${FLAVOR_NAME}'")) | .id' | head -n 1)

if [ -z "$FLAVOR_ID" ]; then
    echo " -> エラー: プラン '${FLAVOR_NAME}' が見つかりませんでした。"
    exit 1
fi
echo " -> Flavor ID: ${FLAVOR_ID}"

echo "[*] イメージ '${IMAGE_NAME}' の Image ID を取得しています..."
IMAGE_RES=$(curl -s -X GET \
  -H "Accept: application/json" \
  -H "X-Auth-Token: ${TOKEN}" \
  ${COMPUTE_API}/images/detail)

IMAGE_ID=$(echo "$IMAGE_RES" | jq -r '.images[] | select(.name | contains("'${IMAGE_NAME}'")) | .id' | head -n 1)

if [ -z "$IMAGE_ID" ]; then
    echo " -> エラー: イメージ '${IMAGE_NAME}' が見つかりませんでした。"
    exit 1
fi
echo " -> Image ID: ${IMAGE_ID}"

echo "[*] スタートアップスクリプトを生成しています..."
STARTUP_SCRIPT=$(cat <<EOF
#!/bin/bash
yum install -y git
git clone https://github.com/nicklegr/docker_https_proxy.git /root/docker_https_proxy
cd /root/docker_https_proxy
./install_docker.sh
./setup_auth.sh user "${PROXY_PASSWORD}"
docker compose up -d
EOF
)
USER_DATA=$(echo "$STARTUP_SCRIPT" | base64 -w 0)
echo " -> スクリプトのエンコードが完了しました。"

echo "[*] VPSインスタンス '${INSTANCE_NAME}' を作成しています..."
# ポート開放用に "gncs-ipv4-all" (すべてのIPv4を許可) を指定しています。
# https-proxy (例: port 58673) へアクセスできるようにするためです。
CREATE_RES=$(curl -s -X POST \
  -H "Accept: application/json" \
  -H "Content-Type: application/json" \
  -H "X-Auth-Token: ${TOKEN}" \
  -d '{
    "server": {
        "name": "'${INSTANCE_NAME}'",
        "imageRef": "'${IMAGE_ID}'",
        "flavorRef": "'${FLAVOR_ID}'",
        "adminPass": "'${ADMIN_PASSWORD}'",
        "user_data": "'${USER_DATA}'",
        "security_groups": [
            {"name": "default"},
            {"name": "gncs-ipv4-all"}
        ]
    }
}' ${COMPUTE_API}/servers)

CREATED_ID=$(echo "$CREATE_RES" | jq -r '.server.id')

if [ "$CREATED_ID" == "null" ] || [ -z "$CREATED_ID" ]; then
    echo " -> エラー: インスタンスの作成に失敗しました。"
    echo "$CREATE_RES" | jq .
    exit 1
fi

echo " -> 成功！ VPSインスタンスの作成が開始されました。"
echo " -> インスタンス ID: ${CREATED_ID}"
echo ""
echo "ConoHa コントロールパネルにログインして、IPアドレスや起動状況を確認してください。"
