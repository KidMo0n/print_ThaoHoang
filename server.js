/**
 * server.js — Thao Hoang Orchid Print Server
 *
 * Frontend (index.html) vẽ canvas landscape 1146×862px, xoay 90°CW ngay
 * trên trình duyệt → gửi PNG portrait 862×1146px đến đây.
 * Server chỉ cần nhận PNG và lp in — không cần node-canvas hay ImageMagick.
 *
 * Dependency: express   (npm install express)
 * Chạy      : node server.js
 * Service   : sudo ./install-service.sh
 */

'use strict';

const express  = require('express');
const fs       = require('fs');
const os       = require('os');
const path     = require('path');
const { exec } = require('child_process');

// ─── CONFIG ────────────────────────────────────────────
const PORT    = 4001;
const IS_A    = os.hostname().toLowerCase().includes('aserver');
const PRINTER = IS_A ? 'XP-365B' : 'XP-470B';
const MEDIA   = 'Custom.73x97mm';

console.log('─────────────────────────────────────');
console.log(`  Khu    : ${IS_A ? 'A' : 'B'}`);
console.log(`  Printer: ${PRINTER}`);
console.log(`  Media  : ${MEDIA}`);
console.log(`  Port   : ${PORT}`);
console.log('─────────────────────────────────────');

// ─── APP ───────────────────────────────────────────────
const app = express();
app.use(express.json({ limit: '20mb' }));

app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin',  '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

// ─── HEALTH ────────────────────────────────────────────
// Serve frontend
// - Local LAN : http://192.168.x.x:4001/
// - Tunnel    : https://bserver.thangmotsach.com/in_label/
app.get(['/in_label', '/in_label/'], (req, res) =>
  res.sendFile(path.join(__dirname, 'index.html'))
);
app.get(['/', '/index.html'], (req, res) =>
  res.sendFile(path.join(__dirname, 'index.html'))
);

app.get('/in_label/health', (req, res) => {
  exec(`lpstat -p "${PRINTER}" 2>&1`, (err, out) => {
    res.json({
      status   : 'ok',
      khu      : IS_A ? 'A' : 'B',
      printer  : PRINTER,
      available: !err && !out.toLowerCase().includes('unknown'),
      media    : MEDIA,
      timestamp: new Date().toISOString()
    });
  });
});

// ─── PRINT ─────────────────────────────────────────────
// Frontend đã xoay 90°CW — nhận PNG portrait, ghi tạm, lp in, xóa
app.post('/in_label/print', (req, res) => {
  const { imageBase64, numCopies = 1 } = req.body;
  if (!imageBase64) return res.json({ success: false, message: 'Thieu imageBase64' });

  const copies = Math.max(1, Math.min(999, parseInt(numCopies) || 1));
  const pngTmp = path.join(os.tmpdir(), `label_${Date.now()}.png`);

  console.log(`\n[PRINT] ${new Date().toLocaleString('vi-VN')}  copies=${copies}`);

  try {
    fs.writeFileSync(pngTmp, Buffer.from(imageBase64, 'base64'));
  } catch (e) {
    return res.json({ success: false, message: 'Loi ghi file: ' + e.message });
  }

  const cmd = [
    'lp',
    `-d "${PRINTER}"`,
    `-n ${copies}`,
    `-o media=${MEDIA}`,
    `-o fit-to-page`,
    `-o page-left=0 -o page-right=0 -o page-top=0 -o page-bottom=0`,
    `"${pngTmp}"`
  ].join(' ');

  console.log(`[PRINT] ${cmd}`);

  exec(cmd, (err, _out, stderr) => {
    try { fs.unlinkSync(pngTmp); } catch (_) {}

    if (err) {
      console.error('[PRINT] lp error:', err.message);
      return res.json({ success: false, message: `Loi may in: ${err.message}` });
    }
    if (stderr) console.warn('[PRINT] stderr:', stderr);

    console.log(`[PRINT] OK — ${copies} ban → ${PRINTER}`);
    res.json({
      success: true,
      message: `Da gui ${copies} tem den Khu ${IS_A ? 'A' : 'B'}`,
      details: { printer: PRINTER, copies, ts: new Date().toLocaleString('vi-VN') }
    });
  });
});

// ─── 404 ───────────────────────────────────────────────
app.use((req, res) => res.status(404).json({ success: false, message: 'Not found: ' + req.path }));

// ─── START ─────────────────────────────────────────────
app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n✅  Print server → http://0.0.0.0:${PORT}`);
  console.log(`    GET  /health — kiem tra trang thai`);
  console.log(`    POST /print  — {imageBase64, numCopies}\n`);
});