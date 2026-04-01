#!/usr/bin/env bash
# ═══════════════════════════════════════════════════════════════════════
#  install.sh — Thảo Hoàng Orchid | Print Server
#
#  Cài đặt toàn bộ từ đầu trên Raspberry Pi / Ubuntu 22+:
#    1. Đặt hostname nhận dạng khu (print-khu-a / print-khu-b)
#    2. Node.js 20
#    3. CUPS + cấu hình cho phép truy cập LAN
#    4. Driver XPrinter (từ file .deb đính kèm)
#    5. Máy in tem XP-365B hoặc XP-470B
#    6. LibreOffice headless (chuyển DOCX → PDF khi in A4)
#    7. npm install (express)
#    8. systemd service: print-thaohoang
#
#  Cách dùng:
#    chmod +x install.sh
#    sudo ./install.sh
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
  err "Cần chạy với sudo:\n    sudo ./install.sh"
fi

APP_DIR="$(cd "$(dirname "$0")" && pwd)"
RUN_USER="${SUDO_USER:-$(logname 2>/dev/null || echo 'nobody')}"
RUN_GROUP="$(id -gn "$RUN_USER" 2>/dev/null || echo 'nogroup')"
SERVICE_NAME="print-thaohoang"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
DRIVER_DEB="$APP_DIR/printer-driver-xprinter_3_13_3_all.deb"

echo -e "${BOLD}"
echo "╔══════════════════════════════════════════════════╗"
echo "║   Thảo Hoàng Orchid — Print Server Installer    ║"
echo "╚══════════════════════════════════════════════════╝"
echo -e "${NC}"
echo "  App dir  : $APP_DIR"
echo "  Run user : $RUN_USER ($RUN_GROUP)"
echo "  Service  : $SERVICE_NAME"
echo ""

# ════════════════════════════════════════════════════════
#  BƯỚC 0: Đặt hostname nhận dạng khu
# ════════════════════════════════════════════════════════
step "BƯỚC 0/8: Hostname nhận dạng khu"

CURRENT_HOST="$(hostname)"
echo ""
echo "  Hostname hiện tại: $CURRENT_HOST"
echo ""
echo "  Server này thuộc khu nào?"
echo "  [A] Khu A → hostname: print-khu-a"
echo "  [B] Khu B → hostname: print-khu-b"
echo "  [S] Giữ nguyên hostname: $CURRENT_HOST"
echo ""
read -r -p "  Chọn (A/B/S): " KHU_CHOICE

case "${KHU_CHOICE^^}" in
  A)
    hostnamectl set-hostname print-khu-a
    ok "Hostname đã đặt: print-khu-a (Khu A)"
    KHU="A"
    ;;
  B)
    hostnamectl set-hostname print-khu-b
    ok "Hostname đã đặt: print-khu-b (Khu B)"
    KHU="B"
    ;;
  *)
    warn "Giữ nguyên hostname: $CURRENT_HOST"
    KHU="?"
    ;;
esac

# ════════════════════════════════════════════════════════
#  BƯỚC 1: Node.js 20
# ════════════════════════════════════════════════════════
step "BƯỚC 1/8: Node.js 20"

install_node() {
  info "Đang cài Node.js 20..."
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
}

NODE_BIN=""
if command -v node &>/dev/null; then
  NODE_BIN="$(which node)"
fi
if [ -z "$NODE_BIN" ] && [ -n "$SUDO_USER" ]; then
  NODE_BIN="$(find /home/$SUDO_USER/.nvm/versions/node -name 'node' -type f 2>/dev/null | sort -V | tail -1 || true)"
fi

if [ -z "$NODE_BIN" ]; then
  install_node
  NODE_BIN="$(which node)"
else
  NODE_VER="$($NODE_BIN --version)"
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
NPM_BIN="$(command -v npm 2>/dev/null || true)"
if [ -z "$NPM_BIN" ]; then
  NPM_BIN="$(dirname "$NODE_BIN")/npm"
fi
[ -x "$NPM_BIN" ] || err "Không tìm thấy npm."

ok "Node.js $NODE_VER → $NODE_BIN"
ok "npm → $NPM_BIN"

# ════════════════════════════════════════════════════════
#  BƯỚC 2: CUPS
# ════════════════════════════════════════════════════════
step "BƯỚC 2/8: CUPS"

if dpkg -l cups 2>/dev/null | grep -q '^ii'; then
  ok "CUPS đã cài (bỏ qua)"
else
  info "Cài CUPS..."
  apt-get update -qq
  apt-get install -y cups cups-client
  ok "CUPS đã cài xong"
fi

if ! systemctl is-active cups &>/dev/null; then
  systemctl enable cups
  systemctl start cups
fi

if ! groups "$RUN_USER" | grep -q lpadmin; then
  usermod -aG lpadmin "$RUN_USER"
  ok "Đã thêm $RUN_USER vào nhóm lpadmin"
fi

CUPS_CONF="/etc/cups/cupsd.conf"
if [ ! -f "${CUPS_CONF}.orig" ]; then
  cp "$CUPS_CONF" "${CUPS_CONF}.orig"
fi

cat > "$CUPS_CONF" << 'CUPSCONF'
LogLevel warn
MaxLogSize 0
Port 631
Listen /run/cups/cups.sock
Browsing On
BrowseLocalProtocols dnssd
DefaultAuthType Basic
WebInterface Yes

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
</Location>

<Location /admin/conf>
  AuthType Default
  Require user @SYSTEM
  Order allow,deny
  Allow localhost
  Allow 192.168.0.0/16
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

if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
  ufw allow 631/tcp comment 'CUPS Web UI' 2>/dev/null && ok "ufw: đã mở cổng 631"
fi

systemctl restart cups
sleep 1
ok "CUPS đã cấu hình xong"

LOCAL_IP="$(hostname -I | awk '{print $1}' 2>/dev/null || echo 'x.x.x.x')"
info "CUPS Web UI: http://${LOCAL_IP}:631"

# ════════════════════════════════════════════════════════
#  BƯỚC 3: Driver XPrinter
# ════════════════════════════════════════════════════════
step "BƯỚC 3/8: Driver XPrinter"

if dpkg -l printer-driver-xprinter 2>/dev/null | grep -q '^ii'; then
  ok "Driver XPrinter đã cài (bỏ qua)"
elif [ ! -f "$DRIVER_DEB" ]; then
  warn "Không tìm thấy: $DRIVER_DEB — bỏ qua, thêm thủ công sau"
else
  info "Cài driver từ $DRIVER_DEB..."
  apt-get install -y "$DRIVER_DEB" 2>/dev/null || (dpkg -i "$DRIVER_DEB" && apt-get install -f -y)
  ok "Driver XPrinter đã cài"
fi

# ════════════════════════════════════════════════════════
#  BƯỚC 4: Máy in tem vào CUPS
# ════════════════════════════════════════════════════════
step "BƯỚC 4/8: Máy in tem (XPrinter)"

find_usb_uri() {
  local MODEL="$1"
  lpinfo -v 2>/dev/null | grep -i "usb" | grep -i "$MODEL" | awk '{print $2}' | head -1
}

find_ppd() {
  local MODEL="$1"
  lpinfo -m 2>/dev/null | grep -i "$MODEL" | head -1 | awk '{print $1}' \
  || lpinfo -m 2>/dev/null | grep -i "xprinter" | head -1 | awk '{print $1}' \
  || echo ""
}

add_label_printer() {
  local NAME="$1" MODEL="$2"
  if lpstat -a 2>/dev/null | grep -q "^$NAME "; then
    ok "Máy in $NAME đã có trong CUPS (bỏ qua)"
    return
  fi
  info "Đang dò cổng USB cho $NAME..."
  local URI
  URI="$(find_usb_uri "$MODEL")"
  if [ -z "$URI" ]; then
    warn "Không tìm thấy $NAME qua USB."
    echo ""
    echo "  Thiết bị USB CUPS hiện có:"
    lpinfo -v 2>/dev/null | grep -i usb | sed 's/^/    /' || echo "    (không có)"
    echo ""
    read -r -p "  Nhập URI thủ công hoặc Enter bỏ qua: " URI
    [ -z "$URI" ] && warn "Bỏ qua $NAME" && return
  else
    ok "Tìm thấy URI: $URI"
  fi
  local PPD
  PPD="$(find_ppd "$MODEL")"
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
      -o media=Custom.73x97mm
    warn "Đã thêm $NAME (không tìm thấy PPD — kiểm tra lại driver)"
  fi
  lpadmin -d "$NAME" 2>/dev/null && ok "$NAME đặt làm mặc định"
}

echo ""
echo "  Máy in tem nào lắp trên máy này?"
echo "  [A] Khu A — XP-365B"
echo "  [B] Khu B — XP-470B"
echo "  [S] Bỏ qua"
echo ""
read -r -p "  Chọn (A/B/S): " LABEL_CHOICE

case "${LABEL_CHOICE^^}" in
  A) add_label_printer "XP-365B" "XP-365B" ;;
  B) add_label_printer "XP-470B" "XP-470B" ;;
  *) warn "Bỏ qua máy in tem" ;;
esac

# ════════════════════════════════════════════════════════
#  BƯỚC 5: Máy in A4 vào CUPS
# ════════════════════════════════════════════════════════
step "BƯỚC 5/8: Máy in A4"

echo ""
echo "  Máy in A4 (để in tài liệu DOCX/PDF)."
echo "  Xem danh sách thiết bị USB: lpinfo -v | grep usb"
echo "  Xem máy đã có trong CUPS  : lpstat -a"
echo ""
echo "  Thiết bị USB CUPS hiện có:"
lpinfo -v 2>/dev/null | grep -iv "xprinter\|XP-3\|XP-4" | grep -i "usb" | sed 's/^/    /' || echo "    (không có)"
echo ""

read -r -p "  Nhập tên CUPS cho máy in A4 (VD: Canon-LBP2900) hoặc Enter bỏ qua: " A4_NAME
if [ -n "$A4_NAME" ]; then
  if lpstat -a 2>/dev/null | grep -q "^$A4_NAME "; then
    ok "Máy in $A4_NAME đã có trong CUPS"
  else
    echo "  Các thiết bị USB (bao gồm cả máy in A4):"
    lpinfo -v 2>/dev/null | grep -i usb | sed 's/^/    /'
    echo ""
    read -r -p "  Nhập URI cho $A4_NAME (VD: usb://Canon/LBP2900?serial=...) hoặc Enter bỏ qua: " A4_URI
    if [ -n "$A4_URI" ]; then
      lpadmin -p "$A4_NAME" -E -v "$A4_URI" -o media=A4 -o sides=one-sided 2>/dev/null \
        && ok "Đã thêm $A4_NAME vào CUPS" \
        || warn "Lỗi thêm $A4_NAME — kiểm tra URI"
    else
      warn "Bỏ qua máy in A4"
    fi
  fi
else
  warn "Bỏ qua máy in A4"
  info "Cấu hình sau trong Tab ⚙ Cài đặt trên giao diện web, hoặc sửa config.json"
fi

echo ""
echo "  Máy in trong CUPS hiện tại:"
lpstat -a 2>/dev/null || echo "  (chưa có)"

# ════════════════════════════════════════════════════════
#  BƯỚC 6: LibreOffice headless
# ════════════════════════════════════════════════════════
step "BƯỚC 6/8: LibreOffice headless"

if command -v libreoffice &>/dev/null; then
  LO_VER="$(libreoffice --version 2>/dev/null | head -1)"
  ok "LibreOffice đã có: $LO_VER (bỏ qua)"
else
  info "Cài LibreOffice headless..."
  apt-get install -y libreoffice-headless 2>/dev/null || apt-get install -y libreoffice
  ok "LibreOffice đã cài"
fi

# ════════════════════════════════════════════════════════
#  BƯỚC 7: npm install
# ════════════════════════════════════════════════════════
step "BƯỚC 7/8: npm install (express)"

cd "$APP_DIR"
export PATH="$(dirname "$NODE_BIN"):$PATH"

if [ -d "$APP_DIR/node_modules/express" ]; then
  ok "express đã cài (bỏ qua)"
else
  info "Chạy npm install..."
  "$NPM_BIN" install --omit=dev
  ok "npm install xong"
fi

# ════════════════════════════════════════════════════════
#  BƯỚC 8: systemd service
# ════════════════════════════════════════════════════════
step "BƯỚC 8/8: systemd service — $SERVICE_NAME"

SERVER_FILE="$APP_DIR/server.js"
[ -f "$SERVER_FILE" ] || err "Không tìm thấy server.js tại: $APP_DIR"

# Dừng service cũ nếu tên khác (thaohoang-print-label)
if systemctl is-active thaohoang-print-label &>/dev/null; then
  info "Dừng service cũ thaohoang-print-label..."
  systemctl stop thaohoang-print-label
  systemctl disable thaohoang-print-label 2>/dev/null || true
fi

cat > "$SERVICE_FILE" << UNIT
[Unit]
Description=Thao Hoang Orchid — Print Server
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
echo -e "${BOLD}║              KẾT QUẢ CÀI ĐẶT                    ║${NC}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${NC}"
echo ""
echo "  Node.js  : $NODE_VER → $NODE_BIN"
echo "  App dir  : $APP_DIR"
echo "  Hostname : $(hostname)"
echo "  Khu      : $KHU"
echo "  Service  : $SERVICE_NAME ($STATUS)"
echo ""

if [ "$STATUS" = "active" ]; then
  echo -e "${GREEN}✅  Server đang chạy tại port 4001${NC}"
  echo ""
  echo "  Test local (tem) : curl http://${LOCAL_IP}:4001/in_label/health"
  echo "  Test local (A4)  : curl http://${LOCAL_IP}:4001/in_a4/health"
  echo "  Giao diện web    : http://${LOCAL_IP}:4001"
  echo ""
  echo "  Xem log  : journalctl -u $SERVICE_NAME -f"
  echo "  Khởi lại : sudo systemctl restart $SERVICE_NAME"
  echo ""
  echo -e "${YELLOW}💡  Cấu hình máy in: mở http://${LOCAL_IP}:4001 → Tab ⚙ Cài đặt${NC}"
else
  echo -e "${RED}⚠️   Service chưa active — xem log:${NC}"
  journalctl -u "$SERVICE_NAME" -n 30 --no-pager || true
fi

echo ""
echo -e "${YELLOW}⚠️   BƯỚC TIẾP THEO — Cloudflare Tunnel:${NC}"
echo ""
echo "  Mỗi khu cần 1 tunnel trỏ đến IP tĩnh (KHÔNG dùng localhost):"
echo ""
echo "  Khu A: a_print.thangmotsach.com → http://192.168.0.6:4001"
echo "  Khu B: b_print.thangmotsach.com → http://192.168.2.14:4001"
echo ""
echo "  Cài cloudflared:"
echo "    curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg | \\"
echo "      sudo tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null"
echo "    echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] \\"
echo "      https://pkg.cloudflare.com/cloudflared any main' | \\"
echo "      sudo tee /etc/apt/sources.list.d/cloudflared.list"
echo "    sudo apt-get update && sudo apt-get install -y cloudflared"
echo "    sudo cloudflared service install <TOKEN_CỦA_KHU>"
echo ""
