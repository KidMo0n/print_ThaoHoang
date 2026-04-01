# Thảo Hoàng Orchid — Print Server (`print_ThaoHoang`)

Express server nhận lệnh in từ frontend (web), chuyển tiếp đến máy in qua CUPS.  
Chạy trên Raspberry Pi tại mỗi khu, kết nối ra ngoài qua Cloudflare Tunnel.

---

## 🗺 URL Map

### Tunnel (Internet / WAN)

| Khu   | Chức năng    | URL                                         |
|-------|--------------|---------------------------------------------|
| Tổng  | Landing page | `print.thangmotsach.com` (Cloudflare Pages) |
| Khu A | In tem       | `a_print.thangmotsach.com/in_label`         |
| Khu B | In tem       | `b_print.thangmotsach.com/in_label`         |
| Khu A | In A4        | `a_print.thangmotsach.com/in_a4`            |
| Khu B | In A4        | `b_print.thangmotsach.com/in_a4`            |
| Khu A | Cài đặt      | `a_print.thangmotsach.com` → Tab ⚙          |
| Khu B | Cài đặt      | `b_print.thangmotsach.com` → Tab ⚙          |

### Local LAN (cùng mạng)

| Khu   | URL                                  |
|-------|--------------------------------------|
| Khu A | `http://192.168.0.6:4001`            |
| Khu B | `http://192.168.2.14:4001`           |

> Root `/`, `/in_label`, `/in_a4` đều trả về `index.html`

---

## 📡 API Endpoints

### Cấu hình máy in (mới — v5)

```
GET  /config                → JSON config hiện tại {khu, hostname, config}
POST /config                → Lưu config {printer_label, printer_a4, media_label, servers}
GET  /printers              → Danh sách máy in từ CUPS (lpstat -a)
```

### In tem (XPrinter)

```
GET  /in_label/health       → JSON {khu, printer, available, media}
POST /in_label/print        → In tem PNG
     Body: { imageBase64, numCopies }
```

### In A4

```
GET  /in_a4/health          → JSON {khu, printer_a4, available}
POST /in_a4/print           → In tài liệu A4
     Body: { fileBase64, fileName, numCopies }
     Hỗ trợ: PDF, DOCX, ODT, XLSX, PNG, JPG (tối đa 25MB)
     DOCX/ODT/XLSX → LibreOffice headless → PDF → lp
```

---

## ⚙️ Cài đặt

```bash
chmod +x install.sh
sudo ./install.sh
```

Script tự động cài đặt 8 bước:

| Bước | Nội dung |
|------|----------|
| 0 | Đặt hostname nhận dạng khu (`print-khu-a` / `print-khu-b`) |
| 1 | Node.js 20 |
| 2 | CUPS + cấu hình LAN |
| 3 | Driver XPrinter |
| 4 | Máy in tem (XP-365B hoặc XP-470B) |
| 5 | Máy in A4 (nhập tên CUPS thủ công) |
| 6 | LibreOffice headless |
| 7 | npm install (express) |
| 8 | systemd service **`print-thaohoang`** |

---

## 🖨 Cấu hình máy in (qua giao diện web)

Sau khi cài xong, **không cần sửa code** — cấu hình máy in trực tiếp trên web:

1. Mở `http://<IP>:4001` → Tab **⚙ Cài đặt**
2. Máy in được tự động detect từ CUPS (`lpstat -a`)
3. Chọn từ dropdown hoặc nhập tên thủ công
4. Nhấn **💾 Lưu** — ghi vào `config.json` ngay lập tức, không cần restart

Config lưu tại `config.json` cạnh `server.js`:
```json
{
  "printer_label": "XP-365B",
  "printer_a4": "Canon-LBP2900",
  "media_label": "Custom.73x97mm",
  "servers": {
    "a": "https://a_print.thangmotsach.com",
    "b": "https://b_print.thangmotsach.com"
  }
}
```

> `servers` dùng để trang tổng (Cloudflare Pages) fetch cross-origin tới từng khu.

---

## 📋 Quản lý service

```bash
# Service mới: print-thaohoang
sudo systemctl status  print-thaohoang
sudo systemctl restart print-thaohoang
sudo systemctl stop    print-thaohoang

# Xem log realtime
journalctl -u print-thaohoang -f
```

> **Lưu ý nâng cấp từ phiên bản cũ**: service cũ tên `thaohoang-print-label`
> sẽ tự bị dừng và disable khi chạy `install.sh`.

---

## 🌐 Cloudflare Tunnel

Mỗi khu cần **1 tunnel riêng**, trỏ đến IP tĩnh:

```
Khu A:  a_print.thangmotsach.com  →  http://192.168.0.6:4001
Khu B:  b_print.thangmotsach.com  →  http://192.168.2.14:4001
```

```bash
# Cài cloudflared
curl -fsSL https://pkg.cloudflare.com/cloudflare-public-v2.gpg \
  | sudo tee /usr/share/keyrings/cloudflare-public-v2.gpg >/dev/null
echo 'deb [signed-by=/usr/share/keyrings/cloudflare-public-v2.gpg] \
  https://pkg.cloudflare.com/cloudflared any main' \
  | sudo tee /etc/apt/sources.list.d/cloudflared.list
sudo apt-get update && sudo apt-get install -y cloudflared
sudo cloudflared service install <TOKEN_CỦA_KHU>
```

---

## 📁 Cấu trúc file

```
print_ThaoHoang/
├── server.js                        # Express server (in tem + A4 + config API)
├── index.html                       # Frontend SPA (5 tab: In Tem / Chỉnh Sửa / In Logo / In A4 / Cài đặt)
├── config.json                      # Config máy in (tự tạo, ghi bởi server)
├── package.json
├── install.sh                       # Script cài đặt (service: print-thaohoang)
├── printer-driver-xprinter_*.deb    # Driver XPrinter
├── README.md
└── WORKFLOW.md
```

---

## 🔧 Troubleshooting

### Service không start
```bash
journalctl -u print-thaohoang -n 50 --no-pager
```

### Máy in không nhận lệnh
```bash
lpstat -a                     # danh sách máy in
lpstat -p XP-365B             # trạng thái cụ thể
lpinfo -v | grep usb          # thiết bị USB đang thấy
```

### LibreOffice không convert được
```bash
libreoffice --version
libreoffice --headless --convert-to pdf test.docx
```

### Test API thủ công
```bash
curl http://localhost:4001/config | python3 -m json.tool
curl http://localhost:4001/in_label/health | python3 -m json.tool
curl http://localhost:4001/in_a4/health    | python3 -m json.tool
```
