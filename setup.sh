#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  setup.sh — Thảo Hoàng Orchid | Cài đặt toàn bộ từ đầu
#
#  Cài đặt:
#    1. Node.js 20
#    2. CUPS (print server)
#    3. Driver XPrinter
#    4. Máy in XP-365B / XP-470B vào CUPS
#    5. npm dependencies (express)
#    6. systemd service thaohoang-print-label
#
#  Cách dùng:
#    chmod +x setup.sh
#    sudo ./setup.sh
#
#  Chạy lại an toàn — mọi bước đều kiểm tra trước khi cài.
# ═══════════════════════════════════════════════════════════════════════
set -e

# ── Màu sắc ─────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; BOLD='\033[1m'; NC='\033[0m'

ok()   { echo -e "${GREEN}✅  $*${NC}"; }
info() { echo -e "${BLUE}ℹ️   $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️   $*${NC}"; }
err()  { echo -e "${RED}❌  $*${NC}"; exit 1; }
step() { echo -e "\n${BOLD}${BLUE}══ $* ══${NC}"; }

# ── Kiểm tra sudo ───────────────────────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  err "Cần chạy với sudo:\n    sudo ./setup.sh"
fi

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_USER="${SUDO_USER:-$(logname 2>/dev/null || echo 'nobody')}"
RUN_GROUP="$(id -gn $RUN_USER 2>/dev/null || echo 'nogroup')"
SERVICE_NAME="thaohoang-print-label"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
DRIVER_DEB="$APP_DIR/printer-driver-xprinter_3_13_3_all.deb"

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║   Thảo Hoàng Orchid — Label Print Server Setup  ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  App dir  : $APP_DIR"
echo "  Run user : $RUN_USER ($RUN_GROUP)"
echo ""

# ════════════════════════════════════════════════════════
#  BƯỚC 1: Node.js
# ════════════════════════════════════════════════════════
step "BƯỚC 1/6: Node.js"

install_node() {
  info "Đang cài Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
}

NODE_BIN=""

# Thử tìm node trong PATH
if command -v node &>/dev/null; then
  NODE_BIN="$(which node)"
fi

# Thử tìm trong nvm của SUDO_USER
if [ -z "$NODE_BIN" ] && [ -n "$SUDO_USER" ]; then
  NODE_BIN="$(find /home/$SUDO_USER/.nvm/versions/node -name 'node' -type f 2>/dev/null | sort -V | tail -1 || true)"
fi

if [ -z "$NODE_BIN" ]; then
  install_node
  NODE_BIN="$(which node)"
else
  NODE_VER="$($NODE_BIN --version)"
  NODE_MAJOR="${NODE_VER//[^0-9.]*/}"
  NODE_MAJOR="${NODE_VER:1:2}"
  if [ "$NODE_MAJOR" -lt 18 ] 2>/dev/null; then
    warn "Node.js $NODE_VER quá cũ (cần >= 18). Cài lại..."
    install_node
    NODE_BIN="$(which node)"
  else
    ok "Node.js $NODE_VER đã có → $NODE_BIN (bỏ qua)"
  fi
fi

NODE_VER="$($NODE_BIN --version)"

# Tìm npm: thử PATH trước, fallback về cùng thư mục với node
NPM_BIN="$(command -v npm 2>/dev/null || true)"
if [ -z "$NPM_BIN" ]; then
  NPM_BIN="$(dirname "$NODE_BIN")/npm"
fi
if [ ! -x "$NPM_BIN" ]; then
  err "Không tìm thấy npm. Cài lại Node.js:\n    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -\n    sudo apt-get install -y nodejs"
fi
ok "Node.js $NODE_VER → $NODE_BIN"
ok "npm → $NPM_BIN"

# ════════════════════════════════════════════════════════
#  BƯỚC 2: CUPS
# ════════════════════════════════════════════════════════
step "BƯỚC 2/6: CUPS"

if dpkg -l cups 2>/dev/null | grep -q '^ii'; then
  ok "CUPS đã cài (bỏ qua)"
else
  info "Cài CUPS..."
  apt-get update -qq
  apt-get install -y cups cups-client
  ok "CUPS đã cài xong"
fi

# Đảm bảo CUPS đang chạy
if ! systemctl is-active cups &>/dev/null; then
  systemctl enable cups
  systemctl start cups
  ok "CUPS đã khởi động"
else
  ok "CUPS đang chạy"
fi

# Cho phép user quản lý máy in
if ! groups "$RUN_USER" | grep -q lpadmin; then
  usermod -aG lpadmin "$RUN_USER"
  ok "Đã thêm $RUN_USER vào nhóm lpadmin"
else
  ok "$RUN_USER đã trong nhóm lpadmin (bỏ qua)"
fi

# ── Mở CUPS cho truy cập từ LAN (cổng 631) ─────────────────────
CUPS_CONF="/etc/cups/cupsd.conf"
info "Cấu hình CUPS cho phép truy cập từ LAN..."

# Backup lần đầu
if [ ! -f "${CUPS_CONF}.orig" ]; then
  cp "$CUPS_CONF" "${CUPS_CONF}.orig"
  info "Đã backup: ${CUPS_CONF}.orig"
fi

# Ghi đè toàn bộ cupsd.conf với cấu hình cho phép LAN
cat > "$CUPS_CONF" << 'CUPSCONF'
# cupsd.conf — Thảo Hoàng Orchid
# Cho phép truy cập web UI từ LAN (192.168.x.x)

LogLevel warn
MaxLogSize 0
ErrorLog /var/log/cups/error_log
AccessLog /var/log/cups/access_log
PageLog /var/log/cups/page_log

# Lắng nghe tất cả interface (không chỉ localhost)
Port 631
Listen /run/cups/cups.sock

# Chia sẻ máy in trong mạng
Browsing On
BrowseLocalProtocols dnssd
DefaultAuthType Basic

# Web UI
WebInterface Yes

# Cho phép truy cập từ localhost và LAN
<Location />
  Order allow,deny
  Allow localhost
  Allow 192.168.0.0/16
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
</Location>

<Location /admin>
  Order allow,deny
  Allow localhost
  Allow 192.168.0.0/16
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
</Location>

<Location /admin/conf>
  AuthType Default
  Require user @SYSTEM
  Order allow,deny
  Allow localhost
  Allow 192.168.0.0/16
  Allow 10.0.0.0/8
  Allow 172.16.0.0/12
</Location>

<Policy default>
  JobPrivateAccess default
  JobPrivateValues default
  SubscriptionPrivateAccess default
  SubscriptionPrivateValues default

  <Limit Create-Job Print-Job Print-URI Validate-Job>
    Order deny,allow
  </Limit>

  <Limit Send-Document Send-URI Hold-Job Release-Job Restart-Job Purge-Jobs Set-Job-Attributes Create-Job-Subscription Renew-Subscription Cancel-Subscription Get-Notifications Reprocess-Job Cancel-Current-Job Suspend-Current-Job Resume-Job Cancel-My-Jobs Close-Job CUPS-Move-Job CUPS-Get-Document>
    Require user @OWNER @SYSTEM
    Order deny,allow
  </Limit>

  <Limit CUPS-Add-Modify-Printer CUPS-Delete-Printer CUPS-Add-Modify-Class CUPS-Delete-Class CUPS-Set-Default CUPS-Get-Devices>
    AuthType Default
    Require user @SYSTEM
    Order deny,allow
  </Limit>

  <Limit Pause-Printer Resume-Printer Enable-Printer Disable-Printer Pause-Printer-After-Current-Job Hold-New-Jobs Release-Held-New-Jobs Deactivate-Printer Activate-Printer Restart-Printer Shutdown-Printer Startup-Printer Promote-Job Schedule-Job-After Cancel-Jobs CUPS-Accept-Jobs CUPS-Reject-Jobs>
    AuthType Default
    Require user @SYSTEM
    Order deny,allow
  </Limit>

  <Limit Cancel-Job CUPS-Authenticate-Job>
    Require user @OWNER @SYSTEM
    Order deny,allow
  </Limit>

  <Limit All>
    Order deny,allow
  </Limit>
</Policy>
CUPSCONF

ok "Đã ghi cấu hình CUPS mới"

# Mở firewall cổng 631 nếu ufw đang bật
if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 631/tcp comment 'CUPS Web UI' 2>/dev/null && ok "ufw: đã mở cổng 631"
fi

# Khởi động lại CUPS để áp dụng config mới
systemctl restart cups
sleep 1
ok "CUPS đã restart với cấu hình LAN"

# Lấy IP của máy để hiện thị
LOCAL_IP="$(hostname -I | awk '{print $1}' 2>/dev/null || echo 'x.x.x.x')"
info "Truy cập CUPS Web UI: http://${LOCAL_IP}:631"
info "Đăng nhập bằng tài khoản Linux của user: $RUN_USER" 

# ════════════════════════════════════════════════════════
#  BƯỚC 3: Driver XPrinter
# ════════════════════════════════════════════════════════
step "BƯỚC 3/6: Driver XPrinter"

if dpkg -l printer-driver-xprinter 2>/dev/null | grep -q '^ii'; then
  ok "Driver XPrinter đã cài (bỏ qua)"
else
  if [ ! -f "$DRIVER_DEB" ]; then
    warn "Không tìm thấy file driver: $DRIVER_DEB"
    warn "Bỏ qua bước cài driver — thêm thủ công sau nếu cần."
  else
    info "Cài driver XPrinter từ $DRIVER_DEB..."
    apt-get install -y "$DRIVER_DEB" 2>/dev/null \
      || dpkg -i "$DRIVER_DEB" && apt-get install -f -y
    ok "Driver XPrinter đã cài xong"
  fi
fi

# ════════════════════════════════════════════════════════
#  BƯỚC 4: Thêm máy in vào CUPS
# ════════════════════════════════════════════════════════
step "BƯỚC 4/6: Thêm máy in vào CUPS"

# ── Tìm URI USB của máy in theo model ───────────────────────────
find_usb_uri() {
  local MODEL="$1"
  lpinfo -v 2>/dev/null | grep -i "usb" | grep -i "$MODEL" | awk '{print $2}' | head -1
}

# ── Tìm PPD đúng cho model ───────────────────────────────────────
find_ppd() {
  local MODEL="$1"
  lpinfo -m 2>/dev/null | grep -i "$MODEL" | head -1 | awk '{print $1}' \
  || lpinfo -m 2>/dev/null | grep -i "xprinter" | head -1 | awk '{print $1}' \
  || echo ""
}

# ── Thêm máy in vào CUPS ─────────────────────────────────────────
add_printer() {
  local NAME="$1"
  local MODEL="$2"

  if lpstat -a 2>/dev/null | grep -q "^$NAME "; then
    ok "Máy in $NAME đã có trong CUPS (bỏ qua)"
    return
  fi

  # 1. Tự động dò URI USB
  info "Đang dò cổng USB cho $NAME..."
  local URI
  URI="$(find_usb_uri "$MODEL")"

  if [ -z "$URI" ]; then
    warn "Không tự động tìm thấy $NAME trên USB."
    echo ""
    echo "  Các thiết bị USB CUPS đang thấy:"
    lpinfo -v 2>/dev/null | grep -i usb | sed 's/^/    /' || echo "    (không có)"
    echo ""
    read -r -p "  Nhập URI thủ công (vd: usb://Xprinter/XP-470B?serial=...) hoặc Enter bỏ qua: " URI
    [ -z "$URI" ] && warn "Bỏ qua máy in $NAME" && return
  else
    ok "Tìm thấy URI: $URI"
  fi

  # 2. Tìm đúng PPD/driver
  local PPD
  PPD="$(find_ppd "$MODEL")"

  # 3. Đăng ký vào CUPS
  info "Thêm $NAME vào CUPS..."
  if [ -n "$PPD" ]; then
    lpadmin -p "$NAME" -E -v "$URI" -m "$PPD" \
      -o PageSize=Custom.73x97mm \
      -o media=Custom.73x97mm \
      -o sides=one-sided
    ok "Đã thêm $NAME | driver: $PPD"
  else
    lpadmin -p "$NAME" -E -v "$URI" \
      -o PageSize=Custom.73x97mm \
      -o media=Custom.73x97mm \
      -o sides=one-sided
    warn "Đã thêm $NAME (không tìm thấy PPD — kiểm tra lại driver XPrinter)"
  fi

  # 4. Đặt làm mặc định
  lpadmin -d "$NAME" 2>/dev/null
  ok "$NAME được đặt làm máy in mặc định"
}

echo ""
echo "  Máy in nào lắp trên máy tính này?"
echo "  [A] Khu A — XP-365B"
echo "  [B] Khu B — XP-470B"
echo "  [S] Bỏ qua (thêm thủ công sau)"
echo ""
read -r -p "  Chọn (A/B/S): " PRINTER_CHOICE

case "${PRINTER_CHOICE^^}" in
  A) add_printer "XP-365B" "XP-365B" ;;
  B) add_printer "XP-470B" "XP-470B" ;;
  S|*) warn "Bỏ qua. Thêm sau bằng: sudo lpadmin -p XP-365B -E -v <URI> -m <PPD>" ;;
esac

echo ""
echo "  Máy in hiện có trong CUPS:"
lpstat -a 2>/dev/null || echo "  (chưa có máy in nào)"

# ════════════════════════════════════════════════════════
#  BƯỚC 5: npm install
# ════════════════════════════════════════════════════════
step "BƯỚC 5/6: npm install (express)"

cd "$APP_DIR"
export PATH="$(dirname $NODE_BIN):$PATH"

if [ -d "$APP_DIR/node_modules/express" ]; then
  ok "express đã cài (bỏ qua)"
else
  info "Chạy npm install..."
  "$NPM_BIN" install --omit=dev
  ok "npm install xong"
fi

# ════════════════════════════════════════════════════════
#  BƯỚC 6: systemd service
# ════════════════════════════════════════════════════════
step "BƯỚC 6/6: systemd service"

SERVER_FILE="$APP_DIR/server.js"
if [ ! -f "$SERVER_FILE" ]; then
  err "Không tìm thấy server.js tại: $APP_DIR"
fi

# Ghi/ghi đè service file
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

ok "Đã ghi: $SERVICE_FILE"

systemctl daemon-reload
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

sleep 2
STATUS="$(systemctl is-active $SERVICE_NAME)"

# ════════════════════════════════════════════════════════
#  KẾT QUẢ
# ════════════════════════════════════════════════════════
echo ""
echo -e "${BOLD}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}║                  KẾT QUẢ CÀI ĐẶT                ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Node.js  : $NODE_VER → $NODE_BIN"
echo "  App dir  : $APP_DIR"
echo "  Service  : $SERVICE_NAME"
echo "  Status   : $STATUS"
echo ""

if [ "$STATUS" = "active" ]; then
  echo -e "${GREEN}✅  Cài đặt hoàn tất! Server đang chạy tại port 4001${NC}"
  echo ""
  echo "  Test local  : curl http://localhost:4001/in_label/health"
  echo ""
  echo "  Xem log     : journalctl -u $SERVICE_NAME -f"
  echo "  Khởi lại    : sudo systemctl restart $SERVICE_NAME"
  echo "  Chuyển thư mục: chạy lại sudo ./setup.sh từ vị trí mới"
  echo ""
  echo -e "${YELLOW}⚠️   BƯỚC TIẾP THEO — Cloudflare Tunnel (chưa tự động):${NC}"
  echo "  Server cần tunnel để Cloudflare Pages gọi được từ internet."
  echo "  Nếu chưa có cloudflared:"
  echo "    curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | sudo tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null"
  echo "    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] https://pkg.cloudflare.com/cloudflared any main' | sudo tee /etc/apt/sources.list.d/cloudflared.list"
  echo "    sudo apt-get update && sudo apt-get install -y cloudflared"
  echo "    sudo cloudflared service install <TOKEN_KHU>"
  echo "  Tunnel phải trỏ đến IP tĩnh (không dùng localhost):"
  echo "    Khu A: http://192.168.0.6:4001"
  echo "    Khu B: http://192.168.2.14:4001"
else
  echo -e "${RED}⚠️   Service chưa active — xem log:${NC}"
  journalctl -u "$SERVICE_NAME" -n 30 --no-pager || true
fi
