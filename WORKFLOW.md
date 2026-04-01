# WORKFLOW — Print Server Thảo Hoàng Orchid (`print_ThaoHoang`)

## Luồng tổng thể

```
Người dùng (browser)
  │
  ├─ Mở print.thangmotsach.com    → Cloudflare Pages (landing)
  │     Tab ⚙ Cài đặt             → fetch cross-origin tới 2 khu
  │
  ├─ Truy cập a_print.thangmotsach.com  → Cloudflare Tunnel → Khu A :4001
  └─ Truy cập b_print.thangmotsach.com  → Cloudflare Tunnel → Khu B :4001
           │
           ▼  server.js (Node.js / Express)
           │
           ├─ GET  /              → index.html (SPA 5 tab)
           ├─ GET  /config        → JSON config hiện tại
           ├─ POST /config        → Lưu config.json
           ├─ GET  /printers      → lpstat -a → danh sách CUPS
           │
           ├─ GET  /in_label/health  → JSON trạng thái máy in tem
           ├─ POST /in_label/print   → lp → XP-365B / XP-470B
           │
           ├─ GET  /in_a4/health     → JSON trạng thái máy in A4
           └─ POST /in_a4/print      → [DOCX→PDF via LibreOffice] → lp
```

---

## Chi tiết luồng In Tem

```
Frontend (Tab "In Tem")
  1. Nhận params từ AppSheet URL (tên KH, SĐT, địa chỉ, mã cây, ngày, ghi chú, tổng)
  2. Vẽ canvas 1146×862px (landscape 97×73mm @300dpi)
     ├─ Cột trái (70%): logo + tên công ty / tên KH / SĐT / địa chỉ / vận chuyển
     └─ Cột phải (30%): Zone A: ngày / Zone B: mã cây / Zone C: ghi chú / Zone D: tổng+footer
  3. Xoay 90°CW → PNG 862×1146px (portrait để in)
  4. POST /in_label/print  { imageBase64, numCopies }
           │
           ▼ server.js
  5. Ghi PNG → /tmp/label_<ts>.png
  6. lp -d <printer_label> -n <copies> -o media=<media_label> -o fit-to-page <file>
  7. Xóa file tạm
  8. Response: { success, message, details }
```

## Chi tiết luồng In A4

```
Frontend (Tab "In A4")
  1. Chọn file (PDF / DOCX / ảnh, max 25MB)
  2. Đọc base64 → xem trước
  3. POST /in_a4/print  { fileBase64, fileName, numCopies }
           │
           ▼ server.js
  4. Ghi file → /tmp/a4_<ts>.<ext>

  5a. [PDF / ảnh]    → lp trực tiếp
  5b. [DOCX/ODT/XLSX/PPTX]
       → libreoffice --headless --convert-to pdf
       → lp -d <printer_a4> -n <copies> -o media=A4 -o fit-to-page

  6. Xóa file tạm
  7. Response: { success, message, details }
```

---

## Chi tiết luồng Cài đặt máy in

```
Tab "⚙ Cài đặt"
  │
  ├─ Truy cập qua domain khu (a_print / b_print / IP / localhost)
  │   → SINGLE MODE
  │   → GET /config     → hiển thị config khu hiện tại
  │   → GET /printers   → populate dropdown từ lpstat -a
  │   → POST /config    → lưu printer_label, printer_a4, media_label, servers
  │
  └─ Truy cập qua domain tổng (Cloudflare Pages)
      → DUAL MODE
      → Hiển thị form nhập URL Khu A / Khu B (lưu localStorage)
      → Fetch cross-origin: GET <urlA>/config + <urlA>/printers
      →                     GET <urlB>/config + <urlB>/printers
      → Hiển thị 2 card độc lập, lưu/làm mới từng khu riêng biệt
```

**Detect mode tự động**: server thử fetch `/config` — nếu nhận JSON hợp lệ
→ Single mode; nếu nhận HTML (Cloudflare Pages) → Dual mode.

---

## Nhận dạng khu (server.js)

Server tự nhận dạng khu qua **hostname máy**:

| Hostname chứa           | Khu | Printer label mặc định |
|-------------------------|-----|------------------------|
| `khu-a` / `khua` / `aserver` | A | XP-365B |
| Còn lại                 | B   | XP-470B |

Config thực tế luôn đọc từ `config.json` — hostname chỉ dùng làm fallback
khi `config.json` chưa tồn tại.

```bash
sudo hostnamectl set-hostname print-khu-a   # Khu A
sudo hostnamectl set-hostname print-khu-b   # Khu B
```

---

## systemd service

Service name: **`print-thaohoang`**

```bash
# Quản lý
sudo systemctl start   print-thaohoang
sudo systemctl stop    print-thaohoang
sudo systemctl restart print-thaohoang
sudo systemctl status  print-thaohoang

# Log realtime
journalctl -u print-thaohoang -f

# Health check
curl http://localhost:4001/in_label/health
curl http://localhost:4001/in_a4/health
curl http://localhost:4001/config
```

---

## Cloudflare Tunnel — Cấu hình

```yaml
# /etc/cloudflared/config.yaml  (Khu A)
tunnel: <TUNNEL_ID_KHU_A>
credentials-file: /etc/cloudflared/<TUNNEL_ID_KHU_A>.json

ingress:
  - hostname: a_print.thangmotsach.com
    service: http://192.168.0.6:4001    # IP tĩnh Khu A — KHÔNG dùng localhost
  - service: http_status:404
```

> Mỗi khu dùng **1 tunnel token riêng** (lấy từ Cloudflare Dashboard → Zero Trust → Tunnels).

---

## Deploy / Update

```bash
# 1. Upload lên server
scp -r print_ThaoHoang/ pi@192.168.0.6:~/

# 2. Cài lần đầu
cd ~/print_ThaoHoang
sudo ./install.sh

# 3. Chỉ restart sau khi update code
sudo systemctl restart print-thaohoang

# 4. Kiểm tra
journalctl -u print-thaohoang -f
curl http://localhost:4001/config
```

---

## Troubleshooting

| Triệu chứng | Kiểm tra |
|-------------|----------|
| Service không start | `journalctl -u print-thaohoang -n 50` |
| Máy in không nhận | `lpstat -a` / `lpinfo -v \| grep usb` |
| Tên máy in sai | Tab ⚙ Cài đặt → chọn lại từ dropdown |
| DOCX không in được | `libreoffice --version` / `libreoffice --headless --convert-to pdf test.docx` |
| Trang tổng không thấy khu | Kiểm tra URL trong Tab ⚙ → form "URL Khu A/B" |
| CORS lỗi (trang tổng) | `server.js` đã set `Access-Control-Allow-Origin: *` — kiểm tra Cloudflare không cache |
