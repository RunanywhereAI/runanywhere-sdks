/**
 * Build the app icons from the CANONICAL brand mark.
 *
 * `examples/logo.svg` is already on-brand (#FF6900 -> #FB2C36) and the design
 * guideline is explicit that the mark must never be repainted, so this rasterizes
 * that exact SVG rather than drawing a glyph of its own. Electron does the
 * rasterizing; the ICO and ICNS containers are written by hand (zero deps).
 *
 * Emits:
 *   icon.png   256px — also the Store asset
 *   icon.ico   256/128/64/48/32/16 — Windows
 *   icon.icns  1024..16 — macOS
 *
 *   npm run icon        (from examples/electron/RunAnywhereAI)
 */
import fs from 'node:fs';
import path from 'node:path';

import { app, BrowserWindow, type NativeImage } from 'electron';

const ICO_SIZES = [256, 128, 64, 48, 32, 16] as const;

/**
 * ICNS entries. The OSType for each is what Preview and the Finder look for;
 * `ic07`+ are the PNG-based modern types.
 */
const ICNS_ENTRIES = [
  { type: 'ic10', size: 1024 }, // 512@2x
  { type: 'ic14', size: 512 }, // 256@2x
  { type: 'ic08', size: 512 },
  { type: 'ic13', size: 256 }, // 128@2x
  { type: 'ic07', size: 128 },
  { type: 'ic12', size: 64 }, // 32@2x
  { type: 'ic11', size: 32 }, // 16@2x
] as const;

const OUT_DIR = __dirname;
const LOGO = path.join(__dirname, '..', '..', '..', 'logo.svg');

interface IconEntry {
  readonly size: number;
  readonly data: Buffer;
}

/** ICO container with PNG-compressed entries (Vista+). */
function encodeIco(entries: readonly IconEntry[]): Buffer {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2); // type: icon
  header.writeUInt16LE(entries.length, 4);

  const dir = Buffer.alloc(16 * entries.length);
  let offset = 6 + dir.length;
  entries.forEach((entry, index) => {
    const at = index * 16;
    // 0 encodes 256 in both dimension bytes.
    dir[at] = entry.size >= 256 ? 0 : entry.size;
    dir[at + 1] = entry.size >= 256 ? 0 : entry.size;
    dir.writeUInt16LE(1, at + 4); // colour planes
    dir.writeUInt16LE(32, at + 6); // bits per pixel
    dir.writeUInt32LE(entry.data.length, at + 8);
    dir.writeUInt32LE(offset, at + 12);
    offset += entry.data.length;
  });

  return Buffer.concat([header, dir, ...entries.map((entry) => entry.data)]);
}

/**
 * ICNS container. Layout is a 'icns' magic + total length, then one
 * (OSType, length, payload) chunk per image, all big-endian.
 */
function encodeIcns(entries: readonly { type: string; data: Buffer }[]): Buffer {
  const chunks = entries.map((entry) => {
    const head = Buffer.alloc(8);
    head.write(entry.type, 0, 4, 'ascii');
    head.writeUInt32BE(entry.data.length + 8, 4);
    return Buffer.concat([head, entry.data]);
  });

  const body = Buffer.concat(chunks);
  const header = Buffer.alloc(8);
  header.write('icns', 0, 4, 'ascii');
  header.writeUInt32BE(body.length + 8, 4);
  return Buffer.concat([header, body]);
}

function pngAt(source: NativeImage, size: number, sourceSize: number): Buffer {
  if (size === sourceSize) return source.toPNG();
  return source.resize({ width: size, height: size, quality: 'best' }).toPNG();
}

async function main(): Promise<void> {
  app.disableHardwareAcceleration();
  await app.whenReady();

  const svg = fs.readFileSync(LOGO, 'utf8');
  // Render at 1024 so every downscale is a reduction. Full-bleed with a little
  // breathing room; transparent background so the icon sits cleanly on any
  // taskbar, Dock, or Store surface.
  const canvas = 1024;
  const inset = Math.round(canvas * 0.84);
  const html =
    `<html><body style="margin:0;background:transparent">` +
    `<div style="width:${canvas}px;height:${canvas}px;display:grid;place-items:center">` +
    `<div style="width:${inset}px;height:${inset}px">` +
    svg.replace('<svg ', '<svg style="width:100%;height:100%" ') +
    `</div></div></body></html>`;

  const win = new BrowserWindow({
    width: canvas,
    height: canvas,
    show: false,
    frame: false,
    transparent: true,
    backgroundColor: '#00000000',
  });
  await win.loadURL(`data:text/html;base64,${Buffer.from(html).toString('base64')}`);
  await new Promise((resolve) => setTimeout(resolve, 500)); // let the SVG paint

  const full = await win.capturePage();

  // 256px PNG is the Store asset and the Linux icon.
  fs.writeFileSync(path.join(OUT_DIR, 'icon.png'), pngAt(full, 256, canvas));

  fs.writeFileSync(
    path.join(OUT_DIR, 'icon.ico'),
    encodeIco(ICO_SIZES.map((size) => ({ size, data: pngAt(full, size, canvas) }))),
  );

  fs.writeFileSync(
    path.join(OUT_DIR, 'icon.icns'),
    encodeIcns(ICNS_ENTRIES.map((entry) => ({ type: entry.type, data: pngAt(full, entry.size, canvas) }))),
  );

  console.log(
    `wrote icon.png (256), icon.ico (${ICO_SIZES.join('/')}), and icon.icns ` +
      `(${ICNS_ENTRIES.map((e) => e.size).join('/')}) from the canonical logo.svg`,
  );
  app.exit(0);
}

if (process.versions.electron !== undefined) {
  main().catch((error: unknown) => {
    console.error(error);
    process.exit(1);
  });
} else {
  console.error('Run under Electron:  npm run icon   (electron rasterizes the SVG)');
  process.exit(1);
}
