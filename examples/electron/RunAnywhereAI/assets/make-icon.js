// make-icon.js — build the Windows app icon from the CANONICAL brand mark.
//
// examples/logo.svg is already on-brand (#FF6900 -> #FB2C36) and the design
// guideline is explicit that the mark must never be repainted, so we rasterize
// that exact SVG instead of drawing our own glyph. Electron does the rasterizing
// (already a devDependency of the SDK); the ICO container is written by hand.
//
//   npm run icon        (from examples/electron/RunAnywhereAI)
const fs = require('fs');
const path = require('path');

const SIZES = [256, 128, 64, 48, 32, 16];
const OUT_DIR = __dirname;
const LOGO = path.join(__dirname, '..', '..', '..', 'logo.svg');

// ---- ICO container (PNG-compressed entries; Vista+) -------------------------
function encodeIco(entries) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2); // type: icon
  header.writeUInt16LE(entries.length, 4);
  const dir = Buffer.alloc(16 * entries.length);
  let offset = 6 + dir.length;
  entries.forEach((e, i) => {
    const o = i * 16;
    dir[o] = e.size >= 256 ? 0 : e.size; // 0 encodes 256
    dir[o + 1] = e.size >= 256 ? 0 : e.size;
    dir.writeUInt16LE(1, o + 4); // planes
    dir.writeUInt16LE(32, o + 6); // bpp
    dir.writeUInt32LE(e.data.length, o + 8);
    dir.writeUInt32LE(offset, o + 12);
    offset += e.data.length;
  });
  return Buffer.concat([header, dir, ...entries.map((e) => e.data)]);
}

async function main() {
  const { app, BrowserWindow } = require('electron');
  app.disableHardwareAcceleration();
  await app.whenReady();

  const svg = fs.readFileSync(LOGO, 'utf8');
  // Full-bleed with a little breathing room; transparent background so the icon
  // sits cleanly on any taskbar / Store surface.
  const html = `<html><body style="margin:0;background:transparent">
    <div style="width:256px;height:256px;display:grid;place-items:center">
      <div style="width:216px;height:216px">${svg.replace('<svg ', '<svg style="width:100%;height:100%" ')}</div>
    </div></body></html>`;

  const win = new BrowserWindow({
    width: 256,
    height: 256,
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
  });
  await win.loadURL('data:text/html;base64,' + Buffer.from(html).toString('base64'));
  await new Promise((r) => setTimeout(r, 500)); // let the SVG paint

  const full = await win.capturePage();
  fs.writeFileSync(path.join(OUT_DIR, 'icon.png'), full.toPNG()); // 256px, also the Store asset

  const entries = SIZES.map((size) => ({
    size,
    data: (size === 256 ? full : full.resize({ width: size, height: size, quality: 'best' })).toPNG(),
  }));
  fs.writeFileSync(path.join(OUT_DIR, 'icon.ico'), encodeIco(entries));

  console.log('wrote icon.ico (' + SIZES.join('/') + ') + icon.png from the canonical logo.svg');
  app.exit(0);
}

if (process.versions.electron) {
  main().catch((e) => { console.error(e); process.exit(1); });
} else {
  console.error('Run under Electron:  npm run icon   (electron rasterizes the SVG)');
  process.exit(1);
}
