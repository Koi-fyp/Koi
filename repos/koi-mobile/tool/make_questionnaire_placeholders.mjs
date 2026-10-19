// Writes the PLACEHOLDER questionnaire picture assets (BATCH MOB-1) to
// assets/questionnaire_assets/. They are neutral shapes for development and
// tests only, NOT approved illustrations: the shared asset manifest
// (version "v0-placeholder") must be replaced by the platform's approved,
// versioned manifest before any real questionnaire uses pictures.
//
// Colours are the KOI tokens (lib/theme/koi_colors.dart): neoBlue #2D63EB,
// neoYellow #FFD100, neoMint #2DD36F, neoBlack, neoWhite.
//
// Run: node tool/make_questionnaire_placeholders.mjs
import { writeFileSync, mkdirSync } from 'node:fs';
import { deflateSync } from 'node:zlib';

const SIZE = 120;
const OUT = new URL('../assets/questionnaire_assets/', import.meta.url);

const crcTable = Array.from({ length: 256 }, (_, n) => {
  let c = n;
  for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
  return c >>> 0;
});
const crc32 = (buf) => {
  let c = 0xffffffff;
  for (const b of buf) c = crcTable[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};
const chunk = (type, data) => {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
};

function png(inside, fill) {
  const raw = Buffer.alloc((SIZE * 4 + 1) * SIZE);
  for (let y = 0; y < SIZE; y++) {
    raw[y * (SIZE * 4 + 1)] = 0;
    for (let x = 0; x < SIZE; x++) {
      const d = inside(x + 0.5, y + 0.5); // >0 inside, distance-ish to edge
      const o = y * (SIZE * 4 + 1) + 1 + x * 4;
      const [r, g, b] = d > 5 ? fill : d > 0 ? [0, 0, 0] : [255, 255, 255];
      raw[o] = r; raw[o + 1] = g; raw[o + 2] = b; raw[o + 3] = 255;
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(SIZE, 0);
  ihdr.writeUInt32BE(SIZE, 4);
  ihdr[8] = 8; ihdr[9] = 6; ihdr[10] = 0; ihdr[11] = 0; ihdr[12] = 0;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw)),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

const c = SIZE / 2;
const circle = (x, y) => 44 - Math.hypot(x - c, y - c);
const square = (x, y) => 42 - Math.max(Math.abs(x - c), Math.abs(y - c));
const triangle = (x, y) => {
  // Apex (60,16), base y=100 from x=14..106; distance to the nearest edge.
  const edges = [[60, 16, 106, 100], [106, 100, 14, 100], [14, 100, 60, 16]];
  let min = Infinity;
  for (const [x1, y1, x2, y2] of edges) {
    const nx = y2 - y1, ny = x1 - x2, l = Math.hypot(nx, ny);
    min = Math.min(min, -((x - x1) * nx + (y - y1) * ny) / l);
  }
  return min;
};

mkdirSync(OUT, { recursive: true });
writeFileSync(new URL('placeholder_circle_v1.png', OUT), png(circle, [0x2d, 0x63, 0xeb]));
writeFileSync(new URL('placeholder_square_v1.png', OUT), png(square, [0xff, 0xd1, 0x00]));
writeFileSync(new URL('placeholder_triangle_v1.png', OUT), png(triangle, [0x2d, 0xd3, 0x6f]));
console.log('wrote 3 placeholder PNGs');
