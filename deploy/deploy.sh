#!/usr/bin/env bash
# Deploy Smart Coding Study (backend FastAPI + web Flutter) lên VPS. Chạy từ máy có Flutter:
#
#   deploy/deploy.sh                      # mặc định: host ssh "vps", link https://codewithphuong.jacons-corp.com
#   DEPLOY_HOST=vps deploy/deploy.sh
#
# HTTPS: cert lấy MỘT lần trên VPS (certbot.timer tự gia hạn), deploy chỉ kiểm có cert:
#   ssh vps sudo certbot certonly --nginx -d codewithphuong.jacons-corp.com
#
# Chạy lại bao nhiêu lần cũng được (idempotent). Chỉ chạm tài nguyên của app này:
# /opt/smart-coding-study, user/role smartcs, DB smart_coding_study, /etc/smart-coding-study.env,
# unit smart-coding-study-api, site nginx smart-coding-study.conf (reload chỉ khi `nginx -t` sạch).
set -euo pipefail

HOST="${DEPLOY_HOST:-vps}"
DOMAIN=codewithphuong.jacons-corp.com
# Web và iOS cùng gọi origin này (iOS chặn HTTP thường). nginx: deploy/nginx/smart-coding-study.conf.
PUBLIC_URL="https://$DOMAIN"
# Chế độ mở (demo, không màn đăng nhập): request không token = user này. Rỗng → bật lại đăng nhập:
#   DEPLOY_AUTH_OPEN_AS= deploy/deploy.sh
AUTH_OPEN_AS="${DEPLOY_AUTH_OPEN_AS-test@gmail.com}"
# Chỉ nhận dạng email (giá trị đi qua ssh và được ghi vào env file mà shell sẽ source).
if [ -n "$AUTH_OPEN_AS" ] && ! printf '%s' "$AUTH_OPEN_AS" | grep -Eq '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+$'; then
  echo "DEPLOY_AUTH_OPEN_AS không phải email hợp lệ: từ chối" >&2
  exit 1
fi
APP_DIR=/opt/smart-coding-study
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

# Cert phải có TRƯỚC mọi thay đổi trên server (không để nửa chừng: web mới trỏ HTTPS chưa chạy).
# shellcheck disable=SC2029
ssh "$HOST" "test -f /etc/letsencrypt/live/$DOMAIN/fullchain.pem" \
  || { echo "Chưa có cert cho $DOMAIN — chạy: ssh $HOST sudo certbot certonly --nginx -d $DOMAIN" >&2; exit 1; }

echo "==> 1/4 build web (API_URL=$PUBLIC_URL)"
(cd "$ROOT/mobile" && flutter build web --release --dart-define=API_URL="$PUBLIC_URL")

echo "==> 2/4 đồng bộ code lên $HOST:$APP_DIR"
# Thư mục tạm của root (không dùng /tmp dùng chung: user khác có thể đặt sẵn file để root cài).
STAGE=/root/.smart-coding-study-deploy
# shellcheck disable=SC2029  # APP_DIR, STAGE cố ý mở rộng ở máy local
ssh "$HOST" "mkdir -p $APP_DIR/backend $APP_DIR/web && rm -rf $STAGE && install -d -m 700 $STAGE"
rsync -az --delete \
  --exclude .venv --exclude __pycache__ --exclude .pytest_cache --exclude tests --exclude .env \
  --exclude .initial-passwords \
  "$ROOT/backend/" "$HOST:$APP_DIR/backend/"
rsync -az --delete "$ROOT/mobile/build/web/" "$HOST:$APP_DIR/web/"
scp -q "$ROOT/deploy/nginx/smart-coding-study.conf" "$ROOT/deploy/systemd/smart-coding-study-api.service" \
  "$HOST:$STAGE/"

echo "==> 3/4 cài đặt trên server"
# Heredoc nháy đơn: mọi $ bên trong là của server; APP_DIR truyền từ máy local qua môi trường.
# shellcheck disable=SC2029
ssh "$HOST" "APP_DIR=$APP_DIR TMP=$STAGE DOMAIN=$DOMAIN AUTH_OPEN_AS='$AUTH_OPEN_AS' bash -s" <<'REMOTE'
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
    printf "SET log_min_error_statement = panic;\nALTER ROLE smartcs WITH LOGIN PASSWORD '%s';\n" "$PW" | pg
  else
    printf "SET log_min_error_statement = panic;\nCREATE ROLE smartcs WITH LOGIN PASSWORD '%s';\n" "$PW" | pg
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

# Migration; nội dung chỉ nạp khi DB còn rỗng — DB là nguồn chính (admin sửa qua /api/admin), deploy
# KHÔNG ghi đè. Ghi đè có chủ ý: export trước rồi `python -m app.load_content --force` (README).
# Seed user: mật khẩu ban đầu chỉ vào file root 600, log deploy chỉ có số lượng.
( set -a; . "$ENV_FILE"; set +a
  .venv/bin/alembic upgrade head
  # Gán vào biến trước: `echo "$(lệnh)"` nuốt exit code của lệnh nên set -e không dừng được.
  content_out="$(.venv/bin/python -m app.load_content --if-empty)"
  echo "content: $content_out"
  install -d -m 700 /etc/smart-coding-study && chmod 700 /etc/smart-coding-study
  INITIAL_PASSWORDS_FILE=/etc/smart-coding-study/initial-passwords .venv/bin/python -m app.seed_users )

# File mật khẩu dev không bao giờ được nằm trong thư mục app (rsync loại trừ nó nên --delete cũng không
# xoá bản cũ nếu từng có) — xoá trước khi chmod -R mở quyền đọc cho mọi user.
rm -f "$APP_DIR/backend/.initial-passwords"
# Quyền: code của root, chỉ đọc với service; web đọc được bởi nginx.
chown -R root:root "$APP_DIR"
chmod -R u=rwX,go=rX "$APP_DIR"

# Chế độ mở: ghi ngay trước khi restart (bước trước lỗi thì cấu hình cũ giữ nguyên). Xoá dòng cũ rồi
# ghi lại theo lần deploy này (idempotent; systemd đọc qua EnvironmentFile). Giá trị đã kiểm dạng email.
case "$AUTH_OPEN_AS" in *[!A-Za-z0-9._%+@-]*) echo "AUTH_OPEN_AS không hợp lệ" >&2; exit 1 ;; esac
sed -i '/^AUTH_OPEN_AS=/d' "$ENV_FILE"
if [ -n "$AUTH_OPEN_AS" ]; then printf 'AUTH_OPEN_AS=%s\n' "$AUTH_OPEN_AS" >> "$ENV_FILE"; fi

# systemd.
install -m 644 "$TMP/smart-coding-study-api.service" /etc/systemd/system/smart-coding-study-api.service
systemctl daemon-reload
systemctl enable -q smart-coding-study-api
systemctl restart smart-coding-study-api

# nginx: thay site của app này, chỉ reload khi cả cấu hình sạch; lỗi thì trả bản cũ.
# Site mới cần cert của domain; chưa có thì dừng TRƯỚC khi đụng nginx (VPS dùng chung).
if [ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]; then
  echo "Chưa có cert cho $DOMAIN — chạy: sudo certbot certonly --nginx -d $DOMAIN" >&2
  exit 1
fi
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
  curl -fs -o /dev/null http://127.0.0.1:8100/content && break
  sleep 1
done
curl -fsS -o /dev/null http://127.0.0.1:8100/content
# Smoke qua nginx lỗi → trả site cũ + reload (VPS dùng chung: không để cấu hình hỏng chạy tiếp).
rollback_site() {
  echo "smoke qua nginx lỗi — trả cấu hình site cũ" >&2
  if [ -f "$TMP/site.bak" ]; then cp "$TMP/site.bak" "$SITE"; else rm -f "$SITE"; fi
  nginx -t && systemctl reload nginx
  exit 1
}
# Qua nginx bằng HTTPS thật (đúng tên miền + cert), không phụ thuộc DNS của chính VPS.
R="--resolve $DOMAIN:443:127.0.0.1"
curl -fsS -m 10 $R -o /dev/null "https://$DOMAIN/content" || rollback_site
curl -fsS -m 10 $R -o /dev/null "https://$DOMAIN/" || rollback_site
# /api đi qua nginx: chế độ mở → /api/me không token trả 200; tắt → 401.
want=401; [ -n "$AUTH_OPEN_AS" ] && want=200
[ "$(curl -s -m 10 $R -o /dev/null -w '%{http_code}' "https://$DOMAIN/api/me")" = "$want" ] \
  || { echo "/api/me qua nginx không trả $want — kiểm location /api/ và AUTH_OPEN_AS" >&2; rollback_site; }
# Link cũ :8090 chuyển sang domain HTTPS.
[ "$(curl -s -m 10 -o /dev/null -w '%{http_code}' http://127.0.0.1:8090/)" = 308 ] \
  || { echo ":8090 không chuyển hướng 308" >&2; rollback_site; }
rm -rf "$TMP"
echo "server OK"
REMOTE

echo "==> 4/4 xong: $PUBLIC_URL"
