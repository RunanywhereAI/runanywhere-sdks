// make-icon.js — generate the app icon (build/icon.ico + build/icon.png) with
// zero dependencies. Draws the RunAnywhere mark procedurally: a rounded-square
// gradient tile with a white hexagon outline and a check, matching the in-app
// logo. Windows/Store need a real .ico; regenerate with:  node build/make-icon.js
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const SIZE = 256;

// ---- tiny vector helpers (all in 0..SIZE space) ----------------------------
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const mix = (a, b, t) => a + (b - a) * t;

/** Signed distance from p to segment ab (used for stroked paths). */
function distToSegment(px, py, ax, ay, bx, by) {
  const vx = bx - ax;
  const vy = by - ay;
  const wx = px - ax;
  const wy = py - ay;
  const len2 = vx * vx + vy * vy;
  const t = len2 === 0 ? 0 : clamp01((wx * vx + wy * vy) / len2);
  const dx = px - (ax + t * vx);
  const dy = py - (ay + t * vy);
  return Math.hypot(dx, dy);
}

/** Distance to a rounded rectangle's edge (negative inside). */
function sdRoundRect(px, py, cx, cy, hw, hh, r) {
  const qx = Math.abs(px - cx) - (hw - r);
  const qy = Math.abs(py - cy) - (hh - r);
  const ax = Math.max(qx, 0);
  const ay = Math.max(qy, 0);
  return Math.hypot(ax, ay) + Math.min(Math.max(qx, qy), 0) - r;
}

/** Distance to a polygon outline + inside test. */
function polyDistance(px, py, pts) {
  let best = Infinity;
  let inside = false;
  for (let i = 0, j = pts.length - 1; i < pts.length; j = i++) {
    const [ax, ay] = pts[i];
    const [bx, by] = pts[j];
    best = Math.min(best, distToSegment(px, py, ax, ay, bx, by));
    if (ay > py !== by > py && px < ((bx - ax) * (py - ay)) / (by - ay) + ax) inside = !inside;
  }
  return { dist: best, inside };
}

// Hexagon (flat-ish top, like the in-app shield/cube mark).
const HEX = (() => {
  const cx = SIZE / 2;
  const cy = SIZE / 2;
  const r = SIZE * 0.29;
  const pts = [];
  for (let i = 0; i < 6; i++) {
    const a = (Math.PI / 180) * (60 * i - 90);
    pts.push([cx + r * Math.cos(a), cy + r * Math.sin(a)]);
  }
  return pts;
})();

// Check mark inside the hexagon.
const CHECK = [
  [SIZE * 0.40, SIZE * 0.50],
  [SIZE * 0.47, SIZE * 0.575],
  [SIZE * 0.615, SIZE * 0.425],
];

/** Anti-aliased coverage for a signed distance (1 inside, 0 outside). */
const cover = (d, aa = 1.2) => clamp01(0.5 - d / aa);

function renderRGBA() {
  const px = Buffer.alloc(SIZE * SIZE * 4);
  for (let y = 0; y < SIZE; y++) {
    for (let x = 0; x < SIZE; x++) {
      const i = (y * SIZE + x) * 4;
      const fx = x + 0.5;
      const fy = y + 0.5;

      // Background tile: the brand accent ramp (--accent-lift #ff7a3d ->
      // --accent-2 #e64500), matching the in-app logo gradient.
      const t = clamp01((fy / SIZE) * 0.85 + (fx / SIZE) * 0.15);
      let r = mix(0xff, 0xe6, t);
      let g = mix(0x7a, 0x45, t);
      let b = mix(0x3d, 0x00, t);

      // Subtle top-left sheen so the tile doesn't read flat.
      const sheen = clamp01(1 - Math.hypot(fx - SIZE * 0.3, fy - SIZE * 0.22) / (SIZE * 0.75)) * 0.16;
      r = mix(r, 255, sheen);
      g = mix(g, 255, sheen);
      b = mix(b, 255, sheen);

      // White hexagon outline.
      const hex = polyDistance(fx, fy, HEX);
      const hexStroke = cover(Math.abs(hex.dist) - SIZE * 0.021);
      // Check mark stroke.
      let checkD = Infinity;
      for (let k = 0; k < CHECK.length - 1; k++) {
        checkD = Math.min(checkD, distToSegment(fx, fy, CHECK[k][0], CHECK[k][1], CHECK[k + 1][0], CHECK[k + 1][1]));
      }
      const checkStroke = cover(checkD - SIZE * 0.024);

      const ink = Math.max(hexStroke, checkStroke);
      r = mix(r, 255, ink);
      g = mix(g, 255, ink);
      b = mix(b, 255, ink);

      // Rounded-square silhouette (alpha).
      const a = cover(sdRoundRect(fx, fy, SIZE / 2, SIZE / 2, SIZE / 2 - 1, SIZE / 2 - 1, SIZE * 0.22));

      px[i] = Math.round(r);
      px[i + 1] = Math.round(g);
      px[i + 2] = Math.round(b);
      px[i + 3] = Math.round(a * 255);
    }
  }
  return px;
}

// ---- PNG encoding (RGBA, filter 0) -----------------------------------------
const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();
function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}
function encodePng(rgba, size) {
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // RGBA
  const raw = Buffer.alloc((size * 4 + 1) * size);
  for (let y = 0; y < size; y++) {
    raw[y * (size * 4 + 1)] = 0; // filter: none
    rgba.copy(raw, y * (size * 4 + 1) + 1, y * size * 4, (y + 1) * size * 4);
  }
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

/** Nearest-neighbour-free box downscale (RGBA) for the smaller ICO entries. */
function resize(rgba, from, to) {
  const out = Buffer.alloc(to * to * 4);
  const ratio = from / to;
  for (let y = 0; y < to; y++) {
    for (let x = 0; x < to; x++) {
      let r = 0;
      let g = 0;
      let b = 0;
      let a = 0;
      let n = 0;
      for (let sy = Math.floor(y * ratio); sy < Math.floor((y + 1) * ratio); sy++) {
        for (let sx = Math.floor(x * ratio); sx < Math.floor((x + 1) * ratio); sx++) {
          const i = (sy * from + sx) * 4;
          r += rgba[i]; g += rgba[i + 1]; b += rgba[i + 2]; a += rgba[i + 3];
          n++;
        }
      }
      const o = (y * to + x) * 4;
      out[o] = Math.round(r / n); out[o + 1] = Math.round(g / n);
      out[o + 2] = Math.round(b / n); out[o + 3] = Math.round(a / n);
    }
  }
  return out;
}

// ---- ICO (PNG-compressed entries; supported by Vista+) ----------------------
function encodeIco(pngs) {
  const header = Buffer.alloc(6);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2); // type: icon
  header.writeUInt16LE(pngs.length, 4);
  const dir = Buffer.alloc(16 * pngs.length);
  let offset = 6 + dir.length;
  pngs.forEach((p, i) => {
    const o = i * 16;
    dir[o] = p.size >= 256 ? 0 : p.size; // 0 means 256
    dir[o + 1] = p.size >= 256 ? 0 : p.size;
    dir[o + 2] = 0; // palette
    dir[o + 3] = 0; // reserved
    dir.writeUInt16LE(1, o + 4); // planes
    dir.writeUInt16LE(32, o + 6); // bpp
    dir.writeUInt32LE(p.data.length, o + 8);
    dir.writeUInt32LE(offset, o + 12);
    offset += p.data.length;
  });
  return Buffer.concat([header, dir, ...pngs.map((p) => p.data)]);
}

const base = renderRGBA();
const sizes = [256, 128, 64, 48, 32, 16];
const entries = sizes.map((s) => ({
  size: s,
  data: encodePng(s === SIZE ? base : resize(base, SIZE, s), s),
}));

const outDir = __dirname;
fs.writeFileSync(path.join(outDir, 'icon.ico'), encodeIco(entries));
fs.writeFileSync(path.join(outDir, 'icon.png'), entries[0].data); // 256px, for the Store listing
console.log('wrote icon.ico (' + sizes.join('/') + ') and icon.png');
