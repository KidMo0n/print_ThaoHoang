# 🌸 Thảo Hoàng Orchid — Hệ thống In Tem Dán Thùng

Hệ thống in tem tự động cho **Thảo Hoàng Orchid**, gồm 2 phần:

- **`index.html`** — web tĩnh trên GitHub Pages, nhận đơn hàng từ AppSheet, vẽ tem bằng Canvas API, gửi đến máy in
- **`server.js`** — Node.js server chạy local tại mỗi khu, nhận PNG, in qua CUPS

---

## 📐 Kiến trúc

```
AppSheet
   │  mở URL kèm params
   ▼
GitHub Pages (index.html)
   │  POST /in_label/print  { imageBase64, numCopies }
   │
   ├──▶  aserver.thangmotsach.com/in_label  (Cloudflare Tunnel → 192.168.0.6:4001)  →  XPrinter XP-365B
   └──▶  bserver.thangmotsach.com/in_label  (Cloudflare Tunnel → 192.168.2.14:4001) →  XPrinter XP-470B
```

**Luồng xử lý:**
1. AppSheet mở URL GitHub Pages kèm thông tin đơn (URL-encoded)
2. `index.html` parse → vẽ tem trên Canvas (1146×862px landscape, 97×73mm @300dpi)
3. Canvas xoay 90°CW ngay trên trình duyệt → PNG portrait 862×1146px
4. POST PNG đến server khu tương ứng
5. Server ghi file tạm → `lp` in qua CUPS → xóa file

---

## 🗂️ Cấu trúc repo

```
in_label/
├── index.html           # Frontend — GitHub Pages
├── server.js            # Print server — chạy local mỗi khu
├── package.json         # npm dependencies (chỉ express)
├── install-service.sh   # Cài systemd service
└── README.md
```

---

## 🖨️ Thông tin máy in

| Khu | Tunnel URL | IP local | Port | Máy in |
|-----|-----------|----------|------|--------|
| A | aserver.thangmotsach.com/in_label | 192.168.0.6 | 4001 | XPrinter XP-365B |
| B | bserver.thangmotsach.com/in_label | 192.168.2.14 | 4001 | XPrinter XP-470B |

Khổ giấy: `Custom.73x97mm` (73×97mm, portrait)

---

## 🚀 Cài đặt Print Server

Làm trên **từng máy** (Khu A và Khu B).

### Yêu cầu

- Ubuntu / Debian Linux
- Node.js 20+
- CUPS đã cài, máy in đã thêm vào hệ thống

### Bước 1 — Cài Node.js (nếu chưa có)

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs
node --version   # cần >= 20
```

### Bước 2 — Lấy code

```bash
git clone https://github.com/YOUR_USERNAME/in_label.git
cd in_label
```

### Bước 3 — Chạy script cài đặt

```bash
chmod +x install-service.sh
sudo ./install-service.sh
```

Script tự động làm:
- Tìm Node.js (hỗ trợ cả nvm)
- `npm install --omit=dev` (chỉ cài `express`)
- Tạo `/etc/systemd/system/thaohoang-print-label.service`
- `systemctl enable` + `systemctl start`

### Bước 4 — Kiểm tra

```bash
# Local
curl http://localhost:4001/in_label/health

# Qua Cloudflare tunnel (từ bất kỳ đâu)
curl https://aserver.thangmotsach.com/in_label/health   # Khu A
curl https://bserver.thangmotsach.com/in_label/health   # Khu B
```

Kết quả mong đợi:
```json
{
  "status": "ok",
  "khu": "A",
  "printer": "XP-365B",
  "available": true,
  "media": "Custom.73x97mm",
  "timestamp": "2026-03-19T10:00:00.000Z"
}
```

---

## ☁️ Cloudflare Tunnel

Mỗi khu cần 1 tunnel trỏ đến IP tĩnh của máy đó (**không dùng `localhost`** vì cloudflared chạy trong Docker).

| Khu | Public hostname | Service |
|-----|----------------|---------|
| A | aserver.thangmotsach.com | http://192.168.0.6:4001 |
| B | bserver.thangmotsach.com | http://192.168.2.14:4001 |

Path prefix: `in_label` → server nhận request tại `/in_label/health` và `/in_label/print`.

---

## 🔧 Quản lý Service

```bash
# Trạng thái
sudo systemctl status thaohoang-print-label

# Log realtime
journalctl -u thaohoang-print-label -f

# Log 50 dòng gần nhất
journalctl -u thaohoang-print-label -n 50 --no-pager

# Khởi động lại (sau khi cập nhật server.js)
sudo systemctl restart thaohoang-print-label

# Dừng / Bật
sudo systemctl stop thaohoang-print-label
sudo systemctl start thaohoang-print-label

# Gỡ cài hoàn toàn
sudo systemctl disable thaohoang-print-label
sudo rm /etc/systemd/system/thaohoang-print-label.service
sudo systemctl daemon-reload
```

---

## 🌐 GitHub Pages

### Bật GitHub Pages

1. Repo → **Settings** → **Pages**
2. Source: **Deploy from a branch** → branch `main`, folder `/ (root)`
3. URL: `https://YOUR_USERNAME.github.io/in_label/`

### Deploy

```bash
git add .
git commit -m "mô tả thay đổi"
git push
# GitHub Pages tự build sau ~1 phút
```

---

## 📱 AppSheet — Formula URL

```
HYPERLINK(
  CONCATENATE(
    "https://YOUR_USERNAME.github.io/in_label/index.html?",
    ENCODEURL(CONCATENATE(
      TEXT([THỜI GIAN LÊN ĐƠN], "DD/MM/YYYY"), "
- ", [THÔNG TIN DÁN THÙNG], "
- MÃ CÂY: ",
      IF(CONTAINS([MÃ CÂY], "-"),
        LEFT([MÃ CÂY], FIND("-", [MÃ CÂY]) - 1),
        [MÃ CÂY]
      ), " - ",
      IF(LEN([LOẠI CÂY]) > 5,
        LEFT(RIGHT([LOẠI CÂY], 5), 1) & "V",
        [LOẠI CÂY]
      ), "
- GHI CHÚ: ", [GHI CHÚ], "
- TỔNG: ", [SỐ THÙNG], " THÙNG"
    ))
  ),
  "IN TEM DÁN THÙNG"
)
```

Thêm `noLogo` cuối URL để ẩn toàn bộ thông tin công ty (logo, tên, website):
```
... TỔNG: 2 THÙNG
noLogo
```

---

## 🎨 Layout Tem

```
┌──────────────────────────────────┬───────────────┐
│  [LOGO]  Thảo Hoàng Orchid       │  12/03/2026   │  ← header (nền đen, chữ trắng)
├──────────────────────────────────┤               │
│                                  │     A33       │  ← mã cây (to)
│   TÊN KHÁCH HÀNG                │      1V       │  ← loại cây
│   (tối đa 3 dòng, chữ to nhất)  │               │
│                                  │  Ghi chú: .. │
│   SĐT                           │               │
│   Địa chỉ                       │  ──────────── │
│                                  │  TỔNG: 2     │
│                                  │  THÙNG       │
├──────────────────────────────────┤  ──────────── │
│        SÂN BAY TẮM NHẬN        │ -Thảo Hoàng- │
└──────────────────────────────────┴───────────────┘

noLogo: bỏ header, bỏ footer "-Thảo Hoàng Orchid-" và website
Canvas: 1146×862px landscape → xoay 90°CW trên trình duyệt → portrait → in
Font: Barlow Condensed (Google Fonts) — hỗ trợ đầy đủ tiếng Việt
```

---

## 📊 Số tem tự động

| Số thùng nhập | Số tem in |
|--------------|-----------|
| ≤ 1 | 2 |
| 2 | 4 |
| 2.3 | 4 (floor × 2) |
| 2.6 | 6 ((floor+1) × 2) |
| 5 | 10 |

---

## 🐛 Troubleshooting

### Service không start

```bash
journalctl -u thaohoang-print-label -n 50 --no-pager

# Thử chạy tay để xem lỗi trực tiếp
node server.js
```

### Tunnel trả về 502

Cloudflare không kết nối được đến server. Kiểm tra:
```bash
# 1. Server có đang chạy không?
sudo systemctl status thaohoang-print-label

# 2. Tunnel config có dùng IP tĩnh không? (không dùng localhost)
#    Đúng:  http://192.168.0.6:4001
#    Sai:   http://localhost:4001  ← lỗi khi cloudflared chạy trong Docker

# 3. Port có đang lắng nghe không?
ss -tlnp | grep 4001

# 4. Firewall
sudo ufw allow 4001
```

### Máy in không in

```bash
# Kiểm tra tên máy in (phải khớp với PRINTER trong server.js)
lpstat -a

# Test in thủ công
lp -d XP-365B -o media=Custom.73x97mm /path/to/test.png
```

### Chữ tiếng Việt bị lỗi

Cần kết nối internet để load **Barlow Condensed** từ Google Fonts. Nếu máy không có net, cần embed font vào HTML.

---

## 🔄 Cập nhật code trên server

```bash
cd /path/to/in_label
git pull
sudo systemctl restart thaohoang-print-label
```

---

## 🖼️ Thay logo

Logo được nhúng base64 trực tiếp trong `index.html` (biến `LOGO_B64`). Để thay:

```bash
python3 -c "
import base64
with open('logo.jpg', 'rb') as f:
    print('data:image/jpeg;base64,' + base64.b64encode(f.read()).decode())
" > logo_b64.txt
# Sau đó thay giá trị LOGO_B64 trong index.html
```

---

*Thảo Hoàng Orchid © 2026 — www.thaohoangorchid.com*