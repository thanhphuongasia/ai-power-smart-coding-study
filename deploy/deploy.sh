#!/usr/bin/env bash
# Deploy Smart Coding Study (backend FastAPI + web Flutter) lên VPS. Chạy từ máy có Flutter:
#
#   deploy/deploy.sh                      # mặc định: host ssh "vps", link http://178.105.5.12:8090
#   DEPLOY_HOST=vps PUBLIC_URL=http://1.2.3.4:8090 deploy/deploy.sh
#
# Chạy lại bao nhiêu lần cũng được (idempotent). Chỉ chạm tài nguyên của app này:
# /opt/smart-coding-study, user/role smartcs, DB smart_coding_study, /etc/smart-coding-study.env,
# unit smart-coding-study-api, site nginx smart-coding-study.conf (reload chỉ khi `nginx -t` sạch).
set -euo pipefail

HOST="${DEPLOY_HOST:-vps}"
PUBLIC_URL="${PUBLIC_URL:-http://178.105.5.12:8090}"
APP_DIR=/opt/smart-coding-study
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "==> 1/4 build web (API_URL=$PUBLIC_URL)"
(cd "$ROOT/mobile" && flutter build web --release --dart-define=API_URL="$PUBLIC_URL")

echo "==> 2/4 đồng bộ code lên $HOST:$APP_DIR"
# Thư mục tạm của root (không dùng /tmp dùng chung: user khác có thể đặt sẵn file để root cài).
STAGE=/root/.smart-coding-study-deploy
# shellcheck disable=SC2029  # APP_DIR, STAGE cố ý mở rộng ở máy local
ssh "$HOST" "mkdir -p $APP_DIR/backend $APP_DIR/web && rm -rf $STAGE && install -d -m 700 $STAGE"
rsync -az --delete \
  --exclude .venv --exclude __pycache__ --exclude .pytest_cache --exclude tests --exclude .env \
  "$ROOT/backend/" "$HOST:$APP_DIR/backend/"
rsync -az --delete "$ROOT/mobile/build/web/" "$HOST:$APP_DIR/web/"
scp -q "$ROOT/deploy/nginx/smart-coding-study.conf" "$ROOT/deploy/systemd/smart-coding-study-api.service" \
  "$HOST:$STAGE/"

echo "==> 3/4 cài đặt trên server"
# Heredoc nháy đơn: mọi $ bên trong là của server; APP_DIR truyền từ máy local qua môi trường.
# shellcheck disable=SC2029
ssh "$HOST" "APP_DIR=$APP_DIR TMP=$STAGE bash -s" <<'REMOTE'
set -euo pipefail
ENV_FILE=/etc/smart-coding-study.env

# User hệ thống riêng, không shell.
id smartcs >/dev/null 2>&1 || useradd --system --no-create-home --shell /usr/sbin/nologin smartcs

# Postgres: role + DB riêng. Mật khẩu sinh trên server, chỉ đi qua stdin của psql (không nằm
# trong argv/log sudo) và chỉ ghi vào ENV_FILE. Env ghi ra file tạm rồi mới mv sau khi đặt mật khẩu.
pg() { runuser -u postgres -- psql -Atq "$@"; }
if [ ! -f "$ENV_FILE" ]; then
  PW="$(openssl rand -hex 24)"
  ( umask 027
    printf 'DATABASE_URL=postgresql+psycopg://smartcs:%s@127.0.0.1:5432/smart_coding_study\nCODE_RUNNER=judge0\nJUDGE0_URL=https://ce.judge0.com\n' "$PW" > "$ENV_FILE.new" )
  chown root:smartcs "$ENV_FILE.new"
  chmod 640 "$ENV_FILE.new"
  if [ "$(pg -c "select count(*) from pg_roles where rolname='smartcs'")" = 1 ]; then
    printf "ALTER ROLE smartcs WITH LOGIN PASSWORD '%s';\n" "$PW" | pg
  else
    printf "CREATE ROLE smartcs WITH LOGIN PASSWORD '%s';\n" "$PW" | pg
  fi
  mv "$ENV_FILE.new" "$ENV_FILE"
  unset PW
fi
if [ "$(pg -c "select count(*) from pg_database where datname='smart_coding_study'")" != 1 ]; then
  runuser -u postgres -- createdb -O smartcs smart_coding_study
fi

# Python venv + thư viện.
cd "$APP_DIR/backend"
[ -x .venv/bin/python ] || python3 -m venv .venv
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q -r requirements.txt

# Migration + nạp nội dung (thay toàn bộ, idempotent).
( set -a; . "$ENV_FILE"; set +a
  .venv/bin/alembic upgrade head
  echo "content version: $(.venv/bin/python -m app.load_content)" )

# Quyền: code của root, chỉ đọc với service; web đọc được bởi nginx.
chown -R root:root "$APP_DIR"
chmod -R u=rwX,go=rX "$APP_DIR"

# systemd.
install -m 644 "$TMP/smart-coding-study-api.service" /etc/systemd/system/smart-coding-study-api.service
systemctl daemon-reload
systemctl enable -q smart-coding-study-api
systemctl restart smart-coding-study-api

# nginx: thay site của app này, chỉ reload khi cả cấu hình sạch; lỗi thì trả bản cũ.
SITE=/etc/nginx/sites-enabled/smart-coding-study.conf
[ -f "$SITE" ] && cp "$SITE" "$TMP/site.bak"
install -m 644 "$TMP/smart-coding-study.conf" "$SITE"
if ! nginx -t 2>/dev/null; then
  if [ -f "$TMP/site.bak" ]; then cp "$TMP/site.bak" "$SITE"; else rm -f "$SITE"; fi
  echo "nginx -t lỗi — đã trả cấu hình cũ, KHÔNG reload" >&2
  nginx -t || true
  exit 1
fi
systemctl reload nginx

# Kiểm nhanh: API trả nội dung qua cả cổng nội bộ lẫn nginx.
for i in $(seq 1 20); do
  curl -fsS -o /dev/null http://127.0.0.1:8100/content && break
  sleep 1
done
curl -fsS -o /dev/null http://127.0.0.1:8100/content
curl -fsS -o /dev/null http://127.0.0.1:8090/content
curl -fsS -o /dev/null http://127.0.0.1:8090/
rm -rf "$TMP"
echo "server OK"
REMOTE

echo "==> 4/4 xong: $PUBLIC_URL"
