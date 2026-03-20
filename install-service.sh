#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════
#  install-service.sh — Thảo Hoàng Orchid Print Server
#  Cài server.js thành systemd service, tự khởi động khi máy bật
#
#  Cách dùng:
#    chmod +x install-service.sh
#    sudo ./install-service.sh
# ═══════════════════════════════════════════════════════════════
set -e

SERVICE_NAME="thaohoang-print-label"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"

# ── Kiểm tra chạy với sudo ──────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  echo "❌  Cần chạy với sudo:"
  echo "    sudo ./install-service.sh"
  exit 1
fi

# ── Xác định thư mục chứa server.js ────────────────────────────
APP_DIR="$(cd "$(dirname "$0")" && pwd)"
SERVER_FILE="$APP_DIR/server.js"

if [ ! -f "$SERVER_FILE" ]; then
  echo "❌  Không tìm thấy server.js tại: $APP_DIR"
  exit 1
fi

# ── Tìm Node.js ─────────────────────────────────────────────────
# Ưu tiên: node trong PATH hệ thống → nvm của SUDO_USER
NODE_BIN="$(which node 2>/dev/null || true)"

if [ -z "$NODE_BIN" ] && [ -n "$SUDO_USER" ]; then
  NODE_BIN="$(find /home/$SUDO_USER/.nvm/versions/node -name "node" -type f 2>/dev/null | sort -V | tail -1 || true)"
fi

if [ -z "$NODE_BIN" ]; then
  echo "❌  Không tìm thấy Node.js. Cài Node 20+ trước:"
  echo "    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
  echo "    sudo apt-get install -y nodejs"
  exit 1
fi

NODE_VER="$($NODE_BIN --version)"
NPM_BIN="$(dirname $NODE_BIN)/npm"
echo "✅  npm → $NPM_BIN"
echo "✅  Node.js $NODE_VER → $NODE_BIN"

# ── npm install (chỉ express) ───────────────────────────────────
echo ""
echo "📦  npm install..."
cd "$APP_DIR"

# Export PATH để npm tìm thấy node (nvm không load khi sudo)
export PATH="$(dirname $NODE_BIN):$PATH"
"$NPM_BIN" install --omit=dev

echo "✅  npm install xong"

# ── User chạy service ───────────────────────────────────────────
RUN_USER="${SUDO_USER:-$(logname 2>/dev/null || echo 'nobody')}"
RUN_GROUP="$(id -gn $RUN_USER 2>/dev/null || echo 'nogroup')"
echo ""
echo "👤  Service chạy dưới user: $RUN_USER ($RUN_GROUP)"

# ── Ghi file systemd service ────────────────────────────────────
cat > "$SERVICE_FILE" << UNIT
[Unit]
Description=Thao Hoang Orchid — Label Print Server
After=network.target cups.service
Wants=cups.service

[Service]
Type=simple
User=${RUN_USER}
Group=${RUN_GROUP}
WorkingDirectory=${APP_DIR}
ExecStart=${NODE_BIN} ${SERVER_FILE}
Restart=on-failure
RestartSec=5s
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

[Install]
WantedBy=multi-user.target
UNIT

echo "📄  Đã ghi: $SERVICE_FILE"

# ── Reload & enable & start ─────────────────────────────────────
systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

sleep 2
STATUS="$(systemctl is-active $SERVICE_NAME)"

echo ""
echo "════════════════════════════════════════"
echo "  Node.js : $NODE_VER"
echo "  App dir : $APP_DIR"
echo "  Service : $SERVICE_NAME"
echo "  Status  : $STATUS"
echo "════════════════════════════════════════"

if [ "$STATUS" = "active" ]; then
  echo "✅  Server đang chạy tại port 4001"
  echo ""
  echo "  Xem log  : journalctl -u $SERVICE_NAME -f"
  echo "  Dừng     : sudo systemctl stop $SERVICE_NAME"
  echo "  Khởi lại : sudo systemctl restart $SERVICE_NAME"
  echo "  Gỡ cài   : sudo systemctl disable $SERVICE_NAME"
  echo ""
  echo "  Kiểm tra : curl http://localhost:4001/in_label/health"
else
  echo "⚠️  Service chưa active — xem log:"
  journalctl -u "$SERVICE_NAME" -n 30 --no-pager || true
fi