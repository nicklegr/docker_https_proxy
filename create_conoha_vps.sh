#!/bin/bash

# =========================================================
# ConoHa VPS Instance Creation Script
# =========================================================

# --- Load Configuration from .env ---
if [ -f .env ]; then
    # .env ファイルを読み込む（コメント行を除外）
    export $(grep -v '^#' .env | xargs)
else
    echo "エラー: .env ファイルが見つかりません。.env.example を参考に作成してください。"
    exit 1
fi

# 必須変数のチェック
REQUIRED_VARS=("API_USER" "API_PASSWORD" "TENANT_ID" "REGION" "ADMIN_PASSWORD" "PROXY_PASSWORD")
for var in "${REQUIRED_VARS[@]}"; do
    if [ -z "${!var}" ]; then
        echo "エラー: .env 内で $var が設定されていません。"
        exit 1
    fi
done

# --- VPS Configuration (Static) ---
FLAVOR_NAME="512mb" # 512MBメモリのプラン
IMAGE_NAME="centos-stream10" # CentOS Stream 10 のイメージ
INSTANCE_NAME="docker-https-proxy"
# =========================================================


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

echo "[*] インスタンスの起動を待機しています（IPアドレスの取得）..."

# インスタンスがACTIVEになり、IPアドレスが割り当てられるまでポーリング
MAX_RETRIES=60
RETRY_COUNT=0
IP_ADDRESS=""

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
    SERVER_DETAIL_RES=$(curl -s -X GET \
        -H "Accept: application/json" \
        -H "X-Auth-Token: ${TOKEN}" \
        ${COMPUTE_API}/servers/${CREATED_ID})

    STATUS=$(echo "$SERVER_DETAIL_RES" | jq -r '.server.status')

    if [ "$STATUS" == "ACTIVE" ]; then
        # jqでIPv4アドレスを抽出 (ConoHaでは通常 ext-net または同等のネットワーク名配下に割り当てられる)
        IP_ADDRESS=$(echo "$SERVER_DETAIL_RES" | jq -r '.server.addresses[][] | select(.version == 4) | .addr' | head -n 1)
        if [ -n "$IP_ADDRESS" ] && [ "$IP_ADDRESS" != "null" ]; then
            break
        fi
    elif [ "$STATUS" == "ERROR" ]; then
        echo " -> エラー: インスタンスの作成がエラー状態になりました。"
        exit 1
    fi

    echo -n "."
    sleep 5
    RETRY_COUNT=$((RETRY_COUNT + 1))
done

echo ""

if [ -z "$IP_ADDRESS" ] || [ "$IP_ADDRESS" == "null" ]; then
    echo " -> タイムアウト: IPアドレスの取得に時間がかかっています。"
    echo " -> ConoHa コントロールパネルにログインして、IPアドレスや起動状況を確認してください。"
else
    echo "========================================================="
    echo " VPSインスタンスが起動しました！"
    echo "========================================================="
    echo " -> IPアドレス: ${IP_ADDRESS}"
    echo " -> 接続方法: ssh root@${IP_ADDRESS}"
    echo ""
    echo " プロキシは数分後に自動でセットアップされます。"
    echo " プロキシURL: ${IP_ADDRESS}:58673"
    echo " -> ユーザー名: user"
    echo " -> パスワード: ${PROXY_PASSWORD}"
    echo "========================================================="
fi
