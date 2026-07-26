// Generates the addon's "M+ over gear" icon from code, so the art is
// reproducible and version-controlled rather than a binary someone has to keep.
// Two outputs from one design:
//   MythicPlusTimerandTools/Media/minimap-icon.tga  64x64 round button, in-game
//   assets/curseforge-icon.png                      512x512 square, CurseForge
// The in-game one bakes its own round gold ring and transparent corners, so the
// minimap button needs no separate (and always mis-centered) tracking border.
// Supersampled for antialiasing; no image libraries, just math and zlib.
import fs from "node:fs";
import zlib from "node:zlib";
import { fileURLToPath } from "node:url";
import path from "node:path";

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const cl = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);

// Renders at OUT*SS and box-downsamples to OUT x OUT RGBA. `round` bakes a gold
// ring with transparent corners (minimap button); otherwise a full square tile.
function render(OUT, SS, round) {
  const W = OUT * SS, cx = W / 2, cy = W / 2, f = W / 256; // geometry authored in a 256 box
  const R = new Float32Array(W * W), G = new Float32Array(W * W), B = new Float32Array(W * W);
  const A = new Float32Array(W * W).fill(1);
  const I = (x, y) => y * W + x;
  const cs = round ? 0.86 : 1; // shrink the art to clear the baked ring

  // Face: a soft dark vignette, the depth a WoW icon has.
  const maxR = Math.hypot(cx, cy);
  for (let y = 0; y < W; y++) for (let x = 0; x < W; x++) {
    const t = cl(Math.hypot(x + 0.5 - cx, y + 0.5 - cy) / maxR), i = I(x, y);
    R[i] = 34 + (12 - 34) * t; G[i] = 25 + (9 - 25) * t; B[i] = 15 + (6 - 15) * t;
  }
  const blend = (x, y, r, g, b, a) => {
    if (a <= 0) return; const i = I(x, y);
    R[i] = R[i] * (1 - a) + r * a; G[i] = G[i] * (1 - a) + g * a; B[i] = B[i] * (1 - a) + b * a;
  };
  const dist = (px, py, x, y) => Math.hypot(px - x, py - y);
  function segDist(px, py, x1, y1, x2, y2) {
    const dx = x2 - x1, dy = y2 - y1, l2 = dx * dx + dy * dy;
    let t = l2 ? ((px - x1) * dx + (py - y1) * dy) / l2 : 0; t = t < 0 ? 0 : t > 1 ? 1 : t;
    return Math.hypot(px - (x1 + t * dx), py - (y1 + t * dy));
  }
  const aa = 0.75 * f;
  const discCov = (px, py, r) => cl(r - dist(px, py, cx, cy) + aa);
  const segCov = (px, py, s, hw) => cl(hw - segDist(px, py, s[0], s[1], s[2], s[3]) + aa);
  const S = (v) => cx + (v * f - cx) * cs; // scale an authored coord about center

  // Gear: an 8-tooth ring behind the letters. Teeth are short, square-cornered
  // nubs (a real cog), not long rounded spokes -- each is a rectangle standing on
  // the gear body, tested in its own radial/tangential frame so the corners stay
  // square rather than getting the round caps a line segment would give.
  const Rb = 88 * f * cs, Rh = 52 * f * cs;
  const toothIn = 80 * f * cs, toothOut = 104 * f * cs, toothHW = 13 * f * cs;
  const NT = 8, dirs = [];
  for (let k = 0; k < NT; k++) {
    const a = (-90 + 360 / NT * k) * Math.PI / 180;
    dirs.push([Math.cos(a), Math.sin(a)]);
  }
  const toothCov = (px, py) => {
    const dx = px - cx, dy = py - cy;
    let best = 0;
    for (const [c, s] of dirs) {
      const r = dx * c + dy * s, t = -dx * s + dy * c; // radial, tangential
      const cov = cl(Math.min(r - toothIn, toothOut - r, toothHW - Math.abs(t)) + aa);
      if (cov > best) best = cov;
    }
    return best;
  };
  // "M+" as thick strokes, centered over the gear.
  const strokes = [
    [S(64), S(162), S(64), S(94)], [S(120), S(162), S(120), S(94)],
    [S(64), S(94), S(92), S(140)], [S(120), S(94), S(92), S(140)],
    [S(168) - 24 * f * cs, cy, S(168) + 24 * f * cs, cy],
    [S(168), cy - 24 * f * cs, S(168), cy + 24 * f * cs],
  ];
  const glyphHW = (i) => (i < 4 ? 8.5 * f * cs : 7.5 * f * cs);

  const GEAR = [224, 165, 78], GOLD = [244, 198, 108], DARK = [8, 5, 3];
  for (let y = 0; y < W; y++) for (let x = 0; x < W; x++) {
    const px = x + 0.5, py = y + 0.5;
    // The gear as one unified ring, so overlapping teeth/body don't double-darken.
    let ring = discCov(px, py, Rb);
    const tc = toothCov(px, py); if (tc > ring) ring = tc;
    const gear = ring * (1 - discCov(px, py, Rh));
    if (gear > 0) blend(x, y, GEAR[0], GEAR[1], GEAR[2], 0.32 * gear);

    // M+ : dark outline first, then gold on top, for contrast over the gear.
    let out = 0, gold = 0;
    for (let i = 0; i < strokes.length; i++) {
      const s = strokes[i];
      const o = segCov(px, py, s, glyphHW(i) + 3.2 * f * cs); if (o > out) out = o;
      const g = segCov(px, py, s, glyphHW(i)); if (g > gold) gold = g;
    }
    if (out > 0) blend(x, y, DARK[0], DARK[1], DARK[2], out);
    if (gold > 0) blend(x, y, GOLD[0], GOLD[1], GOLD[2], gold);
  }

  if (round) {
    // Bake the round gold ring and cut the corners to transparent.
    const outerR = 126 * f, faceR = 111 * f, ringMid = 118.5 * f;
    for (let y = 0; y < W; y++) for (let x = 0; x < W; x++) {
      const dc = dist(x + 0.5, y + 0.5, cx, cy), i = I(x, y);
      // gold ring, brighter along its crown and darker at both edges (a bevel)
      if (dc > faceR - 3 * f) {
        const rc = cl(outerR - dc + aa) * cl(dc - (faceR - 3 * f) + aa);
        const bev = 1 - Math.min(1, Math.abs(dc - ringMid) / (7 * f));
        blend(x, y, 150 + 78 * bev, 110 + 60 * bev, 42 + 30 * bev, rc);
      }
      // a thin dark line where the ring meets the face, for a crisp seam
      const sep = cl(1.4 * f - Math.abs(dc - (faceR - 1 * f)));
      if (sep > 0) blend(x, y, 18, 13, 7, 0.85 * sep);
      A[i] = cl(outerR - dc + aa); // transparent outside the ring
    }
  }

  const out = Buffer.alloc(OUT * OUT * 4);
  for (let oy = 0; oy < OUT; oy++) for (let ox = 0; ox < OUT; ox++) {
    let r = 0, g = 0, b = 0, a = 0;
    for (let sy = 0; sy < SS; sy++) for (let sx = 0; sx < SS; sx++) {
      const i = I(ox * SS + sx, oy * SS + sy); r += R[i]; g += G[i]; b += B[i]; a += A[i];
    }
    const n = SS * SS, p = (oy * OUT + ox) * 4;
    out[p] = Math.round(r / n); out[p + 1] = Math.round(g / n); out[p + 2] = Math.round(b / n);
    out[p + 3] = Math.round((a / n) * 255);
  }
  return out;
}

// 32-bit uncompressed TGA (BGRA, top-left origin), which WoW loads directly.
function writeTGA(file, rgba, OUT) {
  const h = Buffer.from([0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, OUT & 255, OUT >> 8, OUT & 255, OUT >> 8, 32, 0x28]);
  const body = Buffer.alloc(OUT * OUT * 4);
  for (let i = 0; i < OUT * OUT; i++) {
    body[i * 4] = rgba[i * 4 + 2]; body[i * 4 + 1] = rgba[i * 4 + 1];
    body[i * 4 + 2] = rgba[i * 4]; body[i * 4 + 3] = rgba[i * 4 + 3];
  }
  fs.writeFileSync(file, Buffer.concat([h, body]));
}

const CRC = (() => { const t = []; for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; t[n] = c >>> 0; } return t; })();
const crc32 = (buf) => { let c = 0xffffffff; for (let i = 0; i < buf.length; i++) c = CRC[(c ^ buf[i]) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
function pngChunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length, 0);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td), 0);
  return Buffer.concat([len, td, crc]);
}
function writePNG(file, rgba, OUT) {
  const raw = Buffer.alloc((OUT * 4 + 1) * OUT);
  for (let y = 0; y < OUT; y++) {
    raw[y * (OUT * 4 + 1)] = 0;
    rgba.copy(raw, y * (OUT * 4 + 1) + 1, y * OUT * 4, (y + 1) * OUT * 4);
  }
  const ihdr = Buffer.alloc(13); ihdr.writeUInt32BE(OUT, 0); ihdr.writeUInt32BE(OUT, 4); ihdr[8] = 8; ihdr[9] = 6;
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  fs.writeFileSync(file, Buffer.concat([sig, pngChunk("IHDR", ihdr), pngChunk("IDAT", zlib.deflateSync(raw)), pngChunk("IEND", Buffer.alloc(0))]));
}

const mediaDir = path.join(ROOT, "MythicPlusTimerandTools", "Media");
const assetsDir = path.join(ROOT, "assets");
fs.mkdirSync(mediaDir, { recursive: true });
fs.mkdirSync(assetsDir, { recursive: true });

writeTGA(path.join(mediaDir, "minimap-icon.tga"), render(64, 4, true), 64);
writePNG(path.join(assetsDir, "curseforge-icon.png"), render(512, 2, false), 512);

// A preview of the round button composited over a stand-in minimap, so the
// round edge and ring can be checked the way they'll actually be seen.
if (process.argv[2] === "--preview") {
  const prev = render(256, 2, true), n = 256, bg = Buffer.alloc(n * n * 4);
  for (let y = 0; y < n; y++) for (let x = 0; x < n; x++) {
    const p = (y * n + x) * 4;
    const fg = prev, a = fg[p + 3] / 255;
    const br = 74 + (x / n) * 20, bgc = [br, 40, 92]; // purple-ish minimap
    bg[p] = Math.round(bgc[0] * (1 - a) + fg[p] * a);
    bg[p + 1] = Math.round(bgc[1] * (1 - a) + fg[p + 1] * a);
    bg[p + 2] = Math.round(bgc[2] * (1 - a) + fg[p + 2] * a);
    bg[p + 3] = 255;
  }
  writePNG(path.join(process.argv[3] || ".", "preview-onmap.png"), bg, n);
}

console.log("wrote MythicPlusTimerandTools/Media/minimap-icon.tga and assets/curseforge-icon.png");
