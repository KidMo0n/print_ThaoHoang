/**
 * server.js — Thảo Hoàng Orchid | Print Server
 *
 * ┌─────────────────────────────────────────────────────────┐
 *  PATH MAP (local LAN = http://IP:4001 | tunnel = domain)
 *
 *  GET  /                     → index.html  (trang chủ)
 *  GET  /in_label             → index.html  (trang chủ)
 *  GET  /in_label/health      → JSON status máy in tem
 *  POST /in_label/print       → In tem (PNG base64)
 *
 *  GET  /in_a4                → index.html  (trang chủ)
 *  GET  /in_a4/health         → JSON status máy in A4
 *  POST /in_a4/print          → In A4 (PDF/DOCX/IMG base64)
 *
 *  GET  /config               → Lấy config hiện tại (JSON)
 *  POST /config               → Lưu config (printer_label, printer_a4, media_label)
 *  GET  /printers             → Danh sách máy in từ CUPS (lpstat -a)
 * └─────────────────────────────────────────────────────────┘
 *
 * Cloudflare Tunnel routing:
 *   a_print.thangmotsach.com  → http://192.168.0.6:4001
 *   b_print.thangmotsach.com  → http://192.168.2.14:4001
 *
 * Dependency: express  (npm install)
 * Chạy      : node server.js
 * Service   : sudo ./install.sh
 */

'use strict';

const express  = require('express');
const fs       = require('fs');
const os       = require('os');
const path     = require('path');
const { exec } = require('child_process');

// ─── CONFIG ────────────────────────────────────────────────────────────
const PORT        = 4001;
const CONFIG_FILE = path.join(__dirname, 'config.json');

// Nhận dạng khu bằng hostname
const HOSTNAME = os.hostname().toLowerCase();
const IS_A     = HOSTNAME.includes('khu-a') || HOSTNAME.includes('khua') || HOSTNAME.includes('aserver');
const KHU      = IS_A ? 'A' : 'B';

// ── Default config (fallback nếu chưa có config.json) ──────────────────
// servers: URL truy cập từ browser (để frontend fetch cross-khu khi ở trang tổng)
const DEFAULT_CONFIG = {
  printer_label : IS_A ? 'XP-365B'         : 'XP-470B',
  printer_a4    : IS_A ? 'A4-Printer-KhuA' : 'A4-Printer-KhuB',
  media_label   : 'Custom.73x97mm',
  servers: {
    a: 'https://a_print.thangmotsach.com',
    b: 'https://b_print.thangmotsach.com'
  }
};

// ── Load / Save config ─────────────────────────────────────────────────
function loadConfig() {
  try {
    const raw = fs.readFileSync(CONFIG_FILE, 'utf8');
    const cfg = JSON.parse(raw);
    return Object.assign({}, DEFAULT_CONFIG, cfg);
  } catch (_) {
    return Object.assign({}, DEFAULT_CONFIG);
  }
}

function saveConfig(cfg) {
  fs.writeFileSync(CONFIG_FILE, JSON.stringify(cfg, null, 2), 'utf8');
}

// Load lúc khởi động
let CFG = loadConfig();

console.log('──────────────────────────────────────────');
console.log(`  Khu          : ${KHU}`);
console.log(`  Hostname     : ${HOSTNAME}`);
console.log(`  Printer label: ${CFG.printer_label}`);
console.log(`  Printer A4   : ${CFG.printer_a4}`);
console.log(`  Media label  : ${CFG.media_label}`);
console.log(`  Config file  : ${CONFIG_FILE}`);
console.log(`  Port         : ${PORT}`);
console.log('──────────────────────────────────────────');

// ─── APP ───────────────────────────────────────────────────────────────
const app = express();
app.use(express.json({ limit: '25mb' }));

app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin',  '*');
  res.setHeader('Access-Control-Allow-Methods', 'GET, POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

const HTML     = path.join(__dirname, 'index.html');
const sendHTML = (res) => res.sendFile(HTML);

// ─── SERVE HTML ────────────────────────────────────────────────────────
app.get('/',           (_req, res) => sendHTML(res));
app.get('/index.html', (_req, res) => sendHTML(res));
app.get('/in_label',   (_req, res) => sendHTML(res));
app.get('/in_a4',      (_req, res) => sendHTML(res));

// ─── /printers — Danh sách máy in từ CUPS ─────────────────────────────
app.get('/printers', (_req, res) => {
  exec('lpstat -a 2>&1', (err, out) => {
    if (err && !out) {
      return res.json({ success: false, printers: [], message: 'Không lấy được danh sách máy in' });
    }
    // lpstat -a: "PrinterName accepting requests since ..."
    const printers = out
      .split('\n')
      .map(l => l.trim())
      .filter(l => l.length > 0 && !l.toLowerCase().includes('error') && !l.toLowerCase().includes('scheduler'))
      .map(l => l.split(' ')[0])
      .filter(Boolean);
    res.json({ success: true, printers, khu: KHU });
  });
});

// ─── /config GET ──────────────────────────────────────────────────────
app.get('/config', (_req, res) => {
  CFG = loadConfig();
  res.json({ success: true, khu: KHU, hostname: HOSTNAME, config: CFG });
});

// ─── /config POST ─────────────────────────────────────────────────────
app.post('/config', (req, res) => {
  const { printer_label, printer_a4, media_label } = req.body || {};
  if (!printer_label && !printer_a4 && !media_label) {
    return res.json({ success: false, message: 'Không có dữ liệu cần lưu' });
  }

  CFG = loadConfig();
  if (printer_label) CFG.printer_label = printer_label.trim();
  if (printer_a4)    CFG.printer_a4    = printer_a4.trim();
  if (media_label)   CFG.media_label   = media_label.trim();

  try {
    saveConfig(CFG);
    console.log(`[CONFIG] Saved: label=${CFG.printer_label} | a4=${CFG.printer_a4} | media=${CFG.media_label}`);
    res.json({ success: true, message: 'Đã lưu cài đặt máy in', config: CFG });
  } catch (e) {
    res.json({ success: false, message: 'Lỗi ghi file: ' + e.message });
  }
});

// ─── /in_label/health ─────────────────────────────────────────────────
app.get('/in_label/health', (_req, res) => {
  CFG = loadConfig();
  exec(`lpstat -p "${CFG.printer_label}" 2>&1`, (err, out) => {
    res.json({
      status   : 'ok',
      khu      : KHU,
      printer  : CFG.printer_label,
      available: !err && !out.toLowerCase().includes('unknown'),
      media    : CFG.media_label,
      timestamp: new Date().toISOString()
    });
  });
});

// ─── /in_label/print ──────────────────────────────────────────────────
app.post('/in_label/print', (req, res) => {
  CFG = loadConfig();
  const { imageBase64, numCopies = 1 } = req.body;
  if (!imageBase64) return res.json({ success: false, message: 'Thiếu imageBase64' });

  const copies = Math.max(1, Math.min(999, parseInt(numCopies) || 1));
  const pngTmp = path.join(os.tmpdir(), `label_${Date.now()}.png`);

  console.log(`\n[LABEL] ${new Date().toLocaleString('vi-VN')}  copies=${copies}  printer=${CFG.printer_label}`);

  try {
    fs.writeFileSync(pngTmp, Buffer.from(imageBase64, 'base64'));
  } catch (e) {
    return res.json({ success: false, message: 'Lỗi ghi file: ' + e.message });
  }

  const cmd = [
    'lp',
    `-d "${CFG.printer_label}"`,
    `-n ${copies}`,
    `-o media=${CFG.media_label}`,
    `-o fit-to-page`,
    `-o page-left=0 -o page-right=0 -o page-top=0 -o page-bottom=0`,
    `"${pngTmp}"`
  ].join(' ');

  console.log(`[LABEL] ${cmd}`);

  exec(cmd, (err, _out, stderr) => {
    try { fs.unlinkSync(pngTmp); } catch (_) {}
    if (err) {
      console.error('[LABEL] lp error:', err.message);
      return res.json({ success: false, message: `Lỗi máy in: ${err.message}` });
    }
    if (stderr) console.warn('[LABEL] stderr:', stderr);
    console.log(`[LABEL] OK — ${copies} bản → ${CFG.printer_label}`);
    res.json({
      success: true,
      message: `Đã gửi ${copies} tem đến Khu ${KHU}`,
      details: { printer: CFG.printer_label, copies, ts: new Date().toLocaleString('vi-VN') }
    });
  });
});

// ─── /in_a4/health ────────────────────────────────────────────────────
app.get('/in_a4/health', (_req, res) => {
  CFG = loadConfig();
  exec(`lpstat -p "${CFG.printer_a4}" 2>&1`, (err, out) => {
    res.json({
      status    : 'ok',
      khu       : KHU,
      printer_a4: CFG.printer_a4,
      available : !err && !out.toLowerCase().includes('unknown'),
      timestamp : new Date().toISOString()
    });
  });
});

// ─── /in_a4/print ─────────────────────────────────────────────────────
app.post('/in_a4/print', async (req, res) => {
  CFG = loadConfig();
  const { fileBase64, fileName = 'document', numCopies = 1 } = req.body;
  if (!fileBase64) return res.json({ success: false, message: 'Thiếu fileBase64' });

  const copies  = Math.max(1, Math.min(99, parseInt(numCopies) || 1));
  const ext     = (fileName.split('.').pop() || 'pdf').toLowerCase();
  const ts      = Date.now();
  const tmpIn   = path.join(os.tmpdir(), `a4_${ts}.${ext}`);
  let   printTarget = tmpIn;

  console.log(`\n[A4] ${new Date().toLocaleString('vi-VN')}  file=${fileName}  copies=${copies}  printer=${CFG.printer_a4}`);

  try {
    fs.writeFileSync(tmpIn, Buffer.from(fileBase64, 'base64'));
  } catch (e) {
    return res.json({ success: false, message: 'Lỗi ghi file: ' + e.message });
  }

  const cleanup = () => {
    try { fs.unlinkSync(tmpIn); } catch (_) {}
    if (printTarget !== tmpIn) { try { fs.unlinkSync(printTarget); } catch (_) {} }
  };

  const isOffice = ['docx','doc','odt','xlsx','xls','pptx','ppt'].includes(ext);
  if (isOffice) {
    const tmpDir  = os.tmpdir();
    const pdfOut  = path.join(tmpDir, path.basename(tmpIn, '.' + ext) + '.pdf');
    try {
      await new Promise((resolve, reject) => {
        const cmd = `libreoffice --headless --convert-to pdf --outdir "${tmpDir}" "${tmpIn}"`;
        console.log(`[A4] convert: ${cmd}`);
        exec(cmd, { timeout: 30000 }, (err, _, stderr) => {
          if (err) return reject(new Error('LibreOffice: ' + (stderr || err.message)));
          if (!fs.existsSync(pdfOut)) return reject(new Error('PDF output không tìm thấy'));
          resolve();
        });
      });
      printTarget = pdfOut;
    } catch (e) {
      cleanup();
      return res.json({ success: false, message: e.message });
    }
  }

  const cmd = [
    'lp',
    `-d "${CFG.printer_a4}"`,
    `-n ${copies}`,
    `-o media=A4`,
    `-o sides=one-sided`,
    `-o fit-to-page`,
    `"${printTarget}"`
  ].join(' ');

  console.log(`[A4] ${cmd}`);

  exec(cmd, (err, _out, stderr) => {
    cleanup();
    if (err) {
      console.error('[A4] lp error:', err.message);
      return res.json({ success: false, message: `Lỗi máy in: ${err.message}` });
    }
    if (stderr) console.warn('[A4] stderr:', stderr);
    console.log(`[A4] OK — ${copies} bản → ${CFG.printer_a4}`);
    res.json({
      success: true,
      message: `Đã gửi ${copies} bản đến Khu ${KHU}`,
      details: { printer: CFG.printer_a4, copies, fileName, ts: new Date().toLocaleString('vi-VN') }
    });
  });
});

// ─── 404 ───────────────────────────────────────────────────────────────
app.use((req, res) => res.status(404).json({ success: false, message: 'Not found: ' + req.path }));

// ─── START ─────────────────────────────────────────────────────────────
app.listen(PORT, '0.0.0.0', () => {
  console.log(`\n✅  Print server → http://0.0.0.0:${PORT}`);
  console.log(`    Khu ${KHU} | Label: ${CFG.printer_label} | A4: ${CFG.printer_a4}`);
  console.log(`    GET  /printers           — danh sách máy in CUPS`);
  console.log(`    GET  /config             — xem config`);
  console.log(`    POST /config             — lưu config`);
  console.log(`    GET  /in_label/health    — status máy in tem`);
  console.log(`    POST /in_label/print     — {imageBase64, numCopies}`);
  console.log(`    GET  /in_a4/health       — status máy in A4`);
  console.log(`    POST /in_a4/print        — {fileBase64, fileName, numCopies}\n`);
});
