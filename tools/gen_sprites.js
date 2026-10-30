// Procedural art for Cafe Tiles (SDF shapes -> anti-aliased PNG) and the atlas file.
// usage (from the project root): node tools/gen_sprites.js [preview.png]
// Writes main/assets/images/*.png and main/assets/game.atlas.
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');

const OUT = 'main/assets/images';
const ATLAS = 'main/assets/game.atlas';
const PREVIEW = process.argv[2];
const ALL = [];
fs.mkdirSync(OUT, { recursive: true });

// ---------- PNG ----------
const CRC_TABLE = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
function crc32(buf) {
  let c = 0xffffffff;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}
function chunk(type, data) {
  const len = Buffer.alloc(4); len.writeUInt32BE(data.length);
  const td = Buffer.concat([Buffer.from(type), data]);
  const crc = Buffer.alloc(4); crc.writeUInt32BE(crc32(td));
  return Buffer.concat([len, td, crc]);
}
function encodePNG(w, h, rgba) {
  const raw = Buffer.alloc((w * 4 + 1) * h);
  for (let y = 0; y < h; y++) {
    raw[y * (w * 4 + 1)] = 0;
    for (let x = 0; x < w * 4; x++) {
      raw[y * (w * 4 + 1) + 1 + x] = Math.max(0, Math.min(255, Math.round(rgba[y * w * 4 + x] * 255)));
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0); ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; ihdr[9] = 6;
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', zlib.deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ---------- SDF ----------
const len = (x, y) => Math.sqrt(x * x + y * y);
const clamp01 = v => Math.max(0, Math.min(1, v));
const circle = (cx, cy, r) => (x, y) => len(x - cx, y - cy) - r;
const ellipse = (cx, cy, rx, ry) => (x, y) => (len((x - cx) / rx, (y - cy) / ry) - 1) * Math.min(rx, ry);
const ellipseR = (cx, cy, rx, ry, deg) => {
  const a = deg * Math.PI / 180, ca = Math.cos(a), sa = Math.sin(a);
  return (x, y) => {
    const dx = x - cx, dy = y - cy;
    const u = dx * ca + dy * sa, v = -dx * sa + dy * ca;
    return (len(u / rx, v / ry) - 1) * Math.min(rx, ry);
  };
};
const ring = (cx, cy, r, t) => (x, y) => Math.abs(len(x - cx, y - cy) - r) - t / 2;
const rbox = (cx, cy, hw, hh, r) => (x, y) => {
  const qx = Math.abs(x - cx) - hw + r, qy = Math.abs(y - cy) - hh + r;
  return len(Math.max(qx, 0), Math.max(qy, 0)) + Math.min(Math.max(qx, qy), 0) - r;
};
const capsule = (ax, ay, bx, by, r) => (x, y) => {
  const pax = x - ax, pay = y - ay, bax = bx - ax, bay = by - ay;
  const h = Math.max(0, Math.min(1, (pax * bax + pay * bay) / (bax * bax + bay * bay)));
  return len(pax - bax * h, pay - bay * h) - r;
};
// Simple polygon (convex or not), optional rounding
const poly = (pts, r = 0) => (x, y) => {
  let d = Infinity, s = 1;
  const n = pts.length;
  for (let i = 0, j = n - 1; i < n; j = i, i++) {
    const [xi, yi] = pts[i], [xj, yj] = pts[j];
    const ex = xj - xi, ey = yj - yi, wx = x - xi, wy = y - yi;
    const h = Math.max(0, Math.min(1, (wx * ex + wy * ey) / (ex * ex + ey * ey)));
    const bx = wx - ex * h, by = wy - ey * h;
    d = Math.min(d, bx * bx + by * by);
    const c1 = y >= yi, c2 = y < yj, c3 = ex * wy > ey * wx;
    if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) s = -s;
  }
  return s * Math.sqrt(d) - r;
};
const polyline = (pts, r) => union(...pts.slice(1).map((p, i) => capsule(pts[i][0], pts[i][1], p[0], p[1], r)));
const union = (...fs) => (x, y) => { let m = Infinity; for (const f of fs) m = Math.min(m, f(x, y)); return m; };
const sub = (a, b) => (x, y) => Math.max(a(x, y), -b(x, y));
const inter = (...fs) => (x, y) => { let m = -Infinity; for (const f of fs) m = Math.max(m, f(x, y)); return m; };
const grow = (f, d) => (x, y) => f(x, y) - d;
const above = y0 => (x, y) => y - y0;     // inside where y < y0
const below = y0 => (x, y) => y0 - y;     // inside where y > y0
const leftOf = x0 => (x, y) => x - x0;
const rightOf = x0 => (x, y) => x0 - x;
const star = (cx, cy, ro, ri, n = 5, rot = -90, r = 0) => {
  const pts = [];
  for (let i = 0; i < n * 2; i++) {
    const a = (rot + i * 180 / n) * Math.PI / 180;
    const rr = i % 2 ? ri : ro;
    pts.push([cx + Math.cos(a) * rr, cy + Math.sin(a) * rr]);
  }
  return poly(pts, r);
};

// ---------- colors ----------
const H = (hex, a = 1) => {
  const v = parseInt(hex.replace('#', ''), 16);
  return [((v >> 16) & 255) / 255, ((v >> 8) & 255) / 255, (v & 255) / 255, a];
};
const mix = (a, b, t) => a.map((v, i) => v + (b[i] - v) * t);
const vgrad = (c1, c2, y0, y1) => (x, y) => mix(c1, c2, clamp01((y - y0) / (y1 - y0)));
const darker = (c, k = 0.8) => [c[0] * k, c[1] * k, c[2] * k, c[3]];
const lighter = (c, k = 0.35) => mix(c, [1, 1, 1, c[3]], k);
const OUTC = H('#3d2b22');   // espresso outline
const WHITE = [1, 1, 1, 1];
const SHINE = [1, 1, 1, 0.45];

// ---------- canvas ----------
function canvas(w, h) {
  const px = new Float32Array(w * h * 4);
  const SS = 4;
  return {
    w, h, px,
    fill(sdf, color) {
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        let cov = 0;
        const d0 = sdf(x + 0.5, y + 0.5);
        if (d0 > 1.5) continue;
        if (d0 < -1.5) cov = 1;
        else {
          for (let sy = 0; sy < SS; sy++) for (let sx = 0; sx < SS; sx++) {
            if (sdf(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS) < 0) cov++;
          }
          cov /= SS * SS;
        }
        if (cov <= 0) continue;
        const c = typeof color === 'function' ? color(x + 0.5, y + 0.5) : color;
        this.blend(x, y, c[0], c[1], c[2], (c[3] ?? 1) * cov);
      }
      return this;
    },
    // outlined silhouette: dark outline around the union, then the parts in order
    parts(list, ow = 4, oc = OUTC) {
      this.fill(grow(union(...list.map(p => p[0])), ow), oc);
      for (const [sdf, color] of list) this.fill(sdf, color);
      return this;
    },
    soft(fn, rgb) {
      for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
        const a = clamp01(fn(x + 0.5, y + 0.5));
        if (a > 0) this.blend(x, y, rgb[0], rgb[1], rgb[2], a);
      }
      return this;
    },
    blend(x, y, r, g, b, a) {
      const i = (y * w + x) * 4;
      const da = px[i + 3];
      const oa = a + da * (1 - a);
      if (oa <= 0) return;
      px[i] = (r * a + px[i] * da * (1 - a)) / oa;
      px[i + 1] = (g * a + px[i + 1] * da * (1 - a)) / oa;
      px[i + 2] = (b * a + px[i + 2] * da * (1 - a)) / oa;
      px[i + 3] = oa;
    },
    save(name) {
      fs.writeFileSync(path.join(OUT, name + '.png'), encodePNG(w, h, px));
      ALL.push({ name, w, h, px });
    },
  };
}

function loadPNG(file) {
  const buf = fs.readFileSync(file);
  let pos = 8, w = 0, h = 0, idatParts = [];
  while (pos < buf.length) {
    const len = buf.readUInt32BE(pos);
    const type = buf.toString('ascii', pos + 4, pos + 8);
    if (type === 'IHDR') {
      w = buf.readUInt32BE(pos + 8);
      h = buf.readUInt32BE(pos + 12);
    } else if (type === 'IDAT') {
      idatParts.push(buf.slice(pos + 8, pos + 8 + len));
    }
    pos += 12 + len;
  }
  const raw = zlib.inflateSync(Buffer.concat(idatParts));
  const px = new Float32Array(w * h * 4);
  const stride = w * 4 + 1;
  for (let y = 0; y < h; y++) {
    for (let x = 0; x < w * 4; x++) {
      px[y * w * 4 + x] = raw[y * stride + 1 + x] / 255;
    }
  }
  return { w, h, px };
}

// ======================================================================= FOOD (112x112)
const S = 112;
const FOOD_NAMES = [
  'food_burger', 'food_coffee', 'food_donut', 'food_pizza',
  'food_cupcake', 'food_fries', 'food_icecream', 'food_hotdog',
  'food_croissant', 'food_cookie', 'food_juice', 'food_cake',
  'food_taco', 'food_sushi', 'food_egg', 'food_cheese'
];

for (const name of FOOD_NAMES) {
  const srcPath = path.join('tools/food_icons', name + '.png');
  const loaded = loadPNG(srcPath);
  fs.copyFileSync(srcPath, path.join(OUT, name + '.png'));
  ALL.push({ name, w: loaded.w, h: loaded.h, px: loaded.px });
}

// ======================================================================= TILES (124x144)
// A thick tile: cream face, caramel wood side, soft shadow baked under it (the face
// center is 14 px above the sprite center: game_view FACE_DY).
function tile(faceTop, faceBot, sideTop, sideBot, rim) {
  const c = canvas(124, 144);
  c.soft((x, y) => 0.3 * clamp01(1 - (rbox(62, 78, 50, 56, 22)(x, y) + 3) / 13), [0.3, 0.18, 0.1]);
  const face = rbox(62, 58, 52, 52, 20);
  const side = rbox(62, 70, 52, 58, 20);
  c.fill(grow(side, 3.2), OUTC);
  c.fill(side, vgrad(sideTop, sideBot, 70, 128));
  c.fill(inter(side, below(119)), rim);
  c.fill(grow(face, 1.2), darker(sideBot, 0.92));
  c.fill(face, vgrad(faceTop, faceBot, 6, 110));
  c.fill(sub(face, rbox(62, 58, 47.5, 47.5, 16)), [1, 1, 1, 0.65]);
  c.fill(ellipseR(36, 21, 17, 5.5, -10), [1, 1, 1, 0.75]);
  c.fill(circle(96, 18, 3), [1, 1, 1, 0.8]);
  return c;
}
tile(H('#fffdf8'), H('#f7eee1'), H('#f2c592'), H('#d8955c'), H('#bf7a43')).save('tile');
{
  const c = tile(H('#fffbe6'), H('#ffe9a6'), H('#ffe07a'), H('#f2b22c'), H('#d9961a'));
  for (const [x, y, r] of [[20, 96, 7], [104, 30, 6], [100, 98, 4.5]]) c.fill(star(x, y, r, r * 0.38, 4, -90, 0.5), [1, 1, 1, 0.9]);
  c.save('tile_gold');
}
{ // white face, added on top when a tile becomes free (additive flash)
  const c = canvas(112, 112);
  c.soft((x, y) => clamp01(1 - (rbox(56, 56, 51, 51, 20)(x, y) + 1) / 3), [1, 1, 1]);
  c.save('tile_flash');
}
{ // silver cloche over a hidden dish
  const c = canvas(112, 104);
  const dome = union(inter(ellipse(56, 78, 46, 54), above(80)), rbox(56, 84, 52, 7, 6));
  const knob = union(circle(56, 20, 8), rbox(56, 28, 4, 5, 2));
  c.parts([[knob, vgrad(H('#ffffff'), H('#c7c9d9'), 12, 32)], [dome, vgrad(H('#fbfbff'), H('#b9bccf'), 24, 92)]], 3.5);
  c.fill(rbox(56, 84, 52, 3, 2), H('#a6a9bf'));
  c.fill(ellipseR(34, 52, 7, 18, 28), [1, 1, 1, 0.85]);
  c.fill(circle(52, 17, 2.5), [1, 1, 1, 0.9]);
  c.fill(star(80, 46, 6, 2.3, 4, -90, 0.5), [1, 1, 1, 0.95]);
  c.save('cloche');
}

// ======================================================================= CUSTOMERS (160x160)
const CUST_NAMES = [
  'cust_cat', 'cust_bear', 'cust_bunny', 'cust_panda',
  'cust_fox', 'cust_frog', 'cust_pig', 'cust_penguin'
];

for (const name of CUST_NAMES) {
  const srcPath = path.join('tools/customer_icons', name + '.png');
  const loaded = loadPNG(srcPath);
  fs.copyFileSync(srcPath, path.join(OUT, name + '.png'));
  ALL.push({ name, w: loaded.w, h: loaded.h, px: loaded.px });
}

// ======================================================================= UI SHAPES (white, tinted at runtime)
{ // panel: white rounded rect (slice9 32)
  const c = canvas(96, 96);
  c.fill(rbox(48, 48, 46, 46, 28), WHITE);
  c.save('panel');
}
{ // frame: white rounded rect with dark outline (slice9 34)
  const c = canvas(96, 96);
  c.fill(rbox(48, 48, 46, 46, 28), OUTC);
  c.fill(rbox(48, 48, 42, 42, 24), WHITE);
  c.save('frame');
}
{ // button: face + darker lip (slice9 34)
  const c = canvas(96, 96);
  c.fill(rbox(48, 50, 45, 44, 26), H('#000000', 0.35));
  c.fill(rbox(48, 48, 44, 44, 26), [0.72, 0.72, 0.72, 1]);
  c.fill(rbox(48, 43, 44, 39, 24), vgrad([1, 1, 1, 1], [0.92, 0.92, 0.92, 1], 4, 82));
  c.fill(rbox(48, 22, 32, 9, 9), [1, 1, 1, 0.35]);
  c.save('btn');
}
{ // round button
  const c = canvas(112, 112);
  c.fill(circle(56, 60, 52), H('#000000', 0.3));
  c.fill(circle(56, 58, 52), [0.72, 0.72, 0.72, 1]);
  c.fill(circle(56, 52, 50), vgrad([1, 1, 1, 1], [0.9, 0.9, 0.9, 1], 2, 102));
  c.fill(ellipse(56, 26, 28, 12), [1, 1, 1, 0.35]);
  c.save('btn_round');
}
{ // tray cell (inset)
  const c = canvas(96, 96);
  c.fill(rbox(48, 48, 44, 44, 20), [0.8, 0.8, 0.8, 1]);
  c.fill(rbox(48, 52, 42, 40, 18), WHITE);
  c.save('cell');
}
{ // speech bubble tail (white + outline on slanted sides)
  const c = canvas(40, 30);
  c.fill(poly([[4, 0], [36, 0], [20, 28]], 1), OUTC);
  c.fill(poly([[9, -4], [31, -4], [20, 20]], 1), WHITE);
  c.save('bubble_tail');
}
{ const c = canvas(16, 16); c.fill(rbox(8, 8, 8, 8, 0), WHITE); c.save('square'); }
{ const c = canvas(32, 32); c.fill(rbox(16, 16, 15, 15, 8), WHITE); c.save('bar'); }

// ======================================================================= ICONS (white glyphs 96x96)
function icon(name, f) {
  const c = canvas(96, 96);
  f(c);
  c.save('icon_' + name);
}
icon('pause', c => { c.fill(rbox(34, 48, 10, 30, 5), WHITE); c.fill(rbox(62, 48, 10, 30, 5), WHITE); });
icon('play', c => c.fill(poly([[30, 16], [80, 48], [30, 80]], 7), WHITE));
icon('home', c => {
  c.fill(sub(union(poly([[48, 10], [88, 46], [8, 46]], 5), rbox(48, 60, 28, 26, 6)), rbox(48, 72, 9, 16, 4)), WHITE);
});
icon('undo', c => {
  c.fill(sub(ring(52, 52, 26, 12), inter(leftOf(52), below(52))), WHITE);
  c.fill(poly([[10, 50], [42, 50], [26, 74]], 3), WHITE);
});
icon('shuffle', c => {
  c.fill(polyline([[12, 72], [30, 72], [58, 28], [72, 28]], 6), WHITE);
  c.fill(polyline([[12, 28], [30, 28], [58, 72], [72, 72]], 6), WHITE);
  c.fill(poly([[70, 14], [90, 28], [70, 42]], 3), WHITE);
  c.fill(poly([[70, 58], [90, 72], [70, 86]], 3), WHITE);
});
icon('bolt', c => c.fill(poly([[58, 6], [18, 54], [44, 54], [34, 90], [78, 38], [52, 38], [64, 6]], 2), WHITE));
icon('ad', c => {
  c.fill(sub(rbox(48, 50, 40, 30, 10), poly([[38, 34], [64, 50], [38, 66]], 2)), WHITE);
  c.fill(capsule(34, 8, 46, 18, 3.5), WHITE);
  c.fill(capsule(62, 8, 50, 18, 3.5), WHITE);
});
function speaker(c) {
  c.fill(poly([[10, 36], [28, 36], [50, 16], [50, 80], [28, 60], [10, 60]], 4), WHITE);
}
icon('sound', c => {
  speaker(c);
  c.fill(inter(ring(50, 48, 18, 7), rightOf(58)), WHITE);
  c.fill(inter(ring(50, 48, 32, 7), rightOf(60)), WHITE);
});
icon('sound_off', c => {
  speaker(c);
  c.fill(capsule(62, 34, 86, 62, 5), WHITE);
  c.fill(capsule(86, 34, 62, 62, 5), WHITE);
});
icon('music', c => {
  c.fill(ellipseR(28, 74, 13, 10, -20), WHITE);
  c.fill(ellipseR(70, 66, 13, 10, -20), WHITE);
  c.fill(rbox(38, 46, 4, 30, 2), WHITE);
  c.fill(rbox(80, 38, 4, 30, 2), WHITE);
  c.fill(poly([[34, 16], [84, 6], [84, 22], [34, 32]], 2), WHITE);
});
icon('music_off', c => {
  c.fill(ellipseR(28, 74, 13, 10, -20), WHITE);
  c.fill(ellipseR(70, 66, 13, 10, -20), WHITE);
  c.fill(rbox(38, 46, 4, 30, 2), WHITE);
  c.fill(rbox(80, 38, 4, 30, 2), WHITE);
  c.fill(poly([[34, 16], [84, 6], [84, 22], [34, 32]], 2), WHITE);
  c.fill(capsule(12, 12, 86, 86, 5), WHITE);
});
icon('check', c => c.fill(polyline([[18, 50], [40, 72], [80, 26]], 8), WHITE));
icon('close', c => { c.fill(capsule(22, 22, 74, 74, 8), WHITE); c.fill(capsule(74, 22, 22, 74, 8), WHITE); });
icon('gear', c => {
  const teeth = [];
  for (let i = 0; i < 8; i++) {
    const a = i * 45;
    const r = a * Math.PI / 180;
    teeth.push(ellipseR(48 + Math.cos(r) * 34, 48 + Math.sin(r) * 34, 10, 8, a));
  }
  c.fill(sub(union(circle(48, 48, 32), ...teeth), circle(48, 48, 12)), WHITE);
});
icon('gamepad', c => {
  const body = union(rbox(48, 50, 36, 20, 16), circle(22, 60, 16), circle(74, 60, 16));
  c.fill(sub(body, union(rbox(26, 50, 3.5, 11, 1.5), rbox(26, 50, 11, 3.5, 1.5), circle(66, 44, 5), circle(76, 56, 5))), WHITE);
});
icon('brush', c => {
  c.fill(rbox(44, 22, 34, 14, 7), WHITE);
  c.fill(polyline([[78, 22], [88, 22], [88, 42], [48, 50], [48, 60]], 4), WHITE);
  c.fill(rbox(48, 76, 8, 18, 4), WHITE);
});
icon('globe', c => {
  c.fill(ring(48, 48, 36, 7), WHITE);
  c.fill(inter(ring(48, 48, 36, 6), (x, y) => Math.abs(len((x - 48) / 0.45, y - 48) - 36) - 3), WHITE);
  c.fill(capsule(16, 48, 80, 48, 3), WHITE);
  c.fill(inter(circle(48, 48, 34), (x, y) => Math.abs(len((x - 48) / 0.45, y - 48) - 36) - 3), WHITE);
  c.fill(inter(circle(48, 48, 34), (x, y) => Math.abs(y - 30) - 2.5), WHITE);
  c.fill(inter(circle(48, 48, 34), (x, y) => Math.abs(y - 66) - 2.5), WHITE);
});
icon('chest', c => {
  c.fill(rbox(48, 64, 36, 22, 6), WHITE);
  c.fill(rbox(48, 36, 38, 12, 6), WHITE);
  c.fill(rbox(48, 48, 10, 12, 3), OUTC);
  c.fill(circle(48, 48, 3), WHITE);
});
icon('fire', c => {
  const flame = union(
    circle(48, 60, 26),
    poly([[24, 60], [48, 14], [72, 60]], 6),
    poly([[36, 44], [62, 20], [54, 56]], 4)
  );
  const cut = union(circle(48, 66, 13), poly([[36, 66], [48, 42], [60, 66]], 3));
  c.fill(sub(flame, cut), WHITE);
});
icon('tasks', c => {
  // clipboard with check lines
  c.fill(sub(rbox(48, 52, 32, 40, 8), rbox(48, 54, 24, 32, 4)), WHITE);
  c.fill(rbox(48, 14, 14, 8, 4), WHITE);
  c.fill(polyline([[28, 40], [33, 45], [41, 35]], 3.5), WHITE);
  c.fill(capsule(48, 40, 66, 40, 3.5), WHITE);
  c.fill(polyline([[28, 62], [33, 67], [41, 57]], 3.5), WHITE);
  c.fill(capsule(48, 62, 66, 62, 3.5), WHITE);
});

// ======================================================================= BAKED ICONS
{ // coin
  const c = canvas(96, 96);
  c.fill(circle(48, 50, 44), OUTC);
  c.fill(circle(48, 50, 40), H('#e09a12'));
  c.fill(circle(48, 46, 40), vgrad(H('#ffe066'), H('#f5b51a'), 6, 86));
  c.fill(ring(48, 46, 28, 5), H('#e09a12'));
  c.fill(star(48, 46, 17, 8, 5, -90, 1.5), H('#e09a12'));
  c.fill(ellipseR(32, 26, 12, 6, -35), [1, 1, 1, 0.55]);
  c.save('coin');
}
{ // gold star
  const c = canvas(128, 128);
  c.fill(star(64, 70, 60, 28, 5, -90, 6), OUTC);
  c.fill(star(64, 70, 53, 24, 5, -90, 4), vgrad(H('#fff07a'), H('#ffb81a'), 12, 118));
  c.fill(ellipseR(50, 46, 12, 6, -30), [1, 1, 1, 0.6]);
  c.save('star');
}
{ // chest
  const c = canvas(128, 128);
  c.fill(ellipse(64, 114, 52, 10), H('#000000', 0.25));
  c.fill(union(rbox(64, 82, 46, 26, 8), rbox(64, 48, 50, 16, 10)), OUTC);
  c.fill(rbox(64, 82, 42, 22, 6), vgrad(H('#a85d2a'), H('#703612'), 60, 104));
  c.fill(rbox(64, 48, 46, 13, 8), vgrad(H('#c77436'), H('#8c4416'), 35, 61));
  c.fill(rbox(32, 82, 6, 22, 2), H('#f5b51a'));
  c.fill(rbox(96, 82, 6, 22, 2), H('#f5b51a'));
  c.fill(rbox(32, 48, 6, 13, 2), H('#f5b51a'));
  c.fill(rbox(96, 48, 6, 13, 2), H('#f5b51a'));
  c.fill(rbox(64, 58, 46, 4, 1), H('#d9910d'));
  c.fill(rbox(64, 60, 11, 13, 4), H('#ffe066'));
  c.fill(circle(64, 58, 3.5), OUTC);
  c.fill(poly([[62, 58], [66, 58], [64, 65]], 1), OUTC);
  c.fill(ellipse(44, 42, 18, 4), [1, 1, 1, 0.4]);
  c.save('chest');
}
{ // VIP crown
  const c = canvas(112, 84);
  const crown = union(poly([[10, 74], [14, 22], [36, 46], [56, 10], [76, 46], [98, 22], [102, 74]], 4), rbox(56, 72, 46, 10, 4));
  c.fill(grow(crown, 4), OUTC);
  c.fill(crown, vgrad(H('#fff07a'), H('#f5a91a'), 10, 82));
  c.fill(rbox(56, 70, 44, 5, 2), H('#e08a12'));
  for (const [x, y, col] of [[14, 22, '#ff5a6e'], [56, 10, '#5ec3ff'], [98, 22, '#7ed957']]) {
    c.fill(circle(x, y, 7), OUTC);
    c.fill(circle(x, y, 5), H(col));
  }
  c.fill(circle(56, 56, 7), H('#ff5a6e'));
  c.fill(ellipseR(36, 52, 8, 3.5, -40), [1, 1, 1, 0.55]);
  c.save('crown');
}
{ // heart
  const c = canvas(64, 64);
  const heart = union(circle(22, 24, 15), circle(42, 24, 15), poly([[9, 31], [55, 31], [32, 57]], 3));
  c.parts([[heart, vgrad(H('#ff7a8a'), H('#e63946'), 8, 56)]], 3);
  c.fill(ellipse(20, 18, 6, 4), [1, 1, 1, 0.6]);
  c.save('heart');
}
{ // pastry display case: wooden cabinet with two shelves (dishes are drawn on it by the GUI:
  // shelf rows at y 46 and 86 of 128), the glass is a separate sprite on top
  const c = canvas(128, 128);
  c.fill(ellipse(64, 122, 56, 6), H('#000000', 0.18));
  const cap = rbox(64, 16, 58, 9, 7);
  const body = rbox(64, 64, 54, 46, 10);
  const base = rbox(64, 112, 60, 10, 6);
  c.parts([[body, H('#fff7ec')], [cap, vgrad(H('#d9a06a'), H('#b07444'), 7, 25)], [base, vgrad(H('#c98a57'), H('#9c623f'), 102, 122)]], 4);
  c.fill(rbox(64, 64, 50, 42, 8), vgrad(H('#fffaf2'), H('#f1e0c6'), 22, 106));
  for (const y of [62, 104]) c.fill(rbox(64, y, 50, 3, 1.5), H('#b07444'));
  c.fill(rbox(64, 13, 44, 2, 1), [1, 1, 1, 0.45]);
  c.fill(rbox(64, 108, 52, 2, 1), [1, 1, 1, 0.3]);
  for (const x of [22, 106]) c.fill(circle(x, 112, 3), H('#ffd23f'));
  c.save('showcase');
}
{ // display case glass: a cool tint, a frame and two diagonal glints
  const c = canvas(128, 128);
  const inside = rbox(64, 64, 50, 42, 8);
  c.fill(inside, [0.86, 0.95, 1, 0.16]);
  c.fill(inter(inside, (x, y) => Math.abs((x - 0.7 * y) - 18) - 6), [1, 1, 1, 0.42]);
  c.fill(inter(inside, (x, y) => Math.abs((x - 0.7 * y) - 36) - 2.5), [1, 1, 1, 0.35]);
  c.fill(sub(rbox(64, 64, 52, 44, 9), inside), [1, 1, 1, 0.55]);
  c.fill(star(100, 30, 6, 2.3, 4, -90, 0.5), [1, 1, 1, 0.95]);
  c.save('showcase_glass');
}
{ // pointing hand
  const c = canvas(112, 112);
  const finger = capsule(44, 14, 44, 60, 11);
  const palm = rbox(58, 74, 30, 26, 14);
  const thumb = capsule(30, 70, 18, 56, 9);
  const knuckles = union(circle(62, 50, 10), circle(80, 54, 10));
  c.parts([[thumb, WHITE], [knuckles, WHITE], [finger, WHITE], [palm, WHITE]], 5);
  c.fill(capsule(56, 92, 82, 92, 3), H('#d9d9e3'));
  c.fill(rbox(58, 104, 26, 6, 3), H('#5ec3ff'));
  c.save('hand');
}

// ======================================================================= FX
{
  const c = canvas(32, 32);
  c.soft((x, y) => {
    const dx = Math.abs(x - 16), dy = Math.abs(y - 16);
    const s = 1 - (Math.sqrt(dx) + Math.sqrt(dy)) / 3.6;
    return Math.max(s * 2.2, 0.55 * (1 - len(dx, dy) / 12));
  }, [1, 1, 1]);
  c.save('spark');
}
{
  const c = canvas(64, 64);
  c.soft((x, y) => Math.pow(Math.max(0, 1 - len(x - 32, y - 32) / 31), 1.3), [1, 1, 1]);
  c.save('puff');
}
{
  const c = canvas(256, 256);
  c.soft((x, y) => {
    const a = Math.atan2(y - 128, x - 128), d = len(x - 128, y - 128) / 126;
    const ray = Math.cos(a * 12) > 0.35 ? 1 : 0;
    return ray * Math.pow(Math.max(0, 1 - d), 0.8) * 0.9;
  }, [1, 1, 1]);
  c.save('rays');
}
{
  const c = canvas(128, 128);
  c.soft((x, y) => Math.pow(Math.max(0, 1 - len(x - 64, y - 64) / 63), 1.6), [1, 1, 1]);
  c.save('glow');
}

{ // soft ring (shockwave)
  const c = canvas(96, 96);
  c.soft((x, y) => Math.exp(-Math.pow((len(x - 48, y - 48) - 40) / 4.5, 2)), [1, 1, 1]);
  c.save('ring');
}
{ // white heart for tinted particles
  const c = canvas(48, 48);
  c.fill(union(circle(16, 17, 11), circle(32, 17, 11), poly([[6.5, 22], [41.5, 22], [24, 42]], 2.5)), WHITE);
  c.save('heart_w');
}
{ // vertical gradient, white -> transparent (background tint)
  const c = canvas(4, 128);
  c.soft((x, y) => 1 - y / 128, [1, 1, 1]);
  c.save('grad');
}
{ // coffee beans and dots, tiled over the background (white, tinted)
  const c = canvas(128, 128);
  const bean = (x, y, deg) => {
    const r = deg * Math.PI / 180, cs = Math.cos(r), sn = Math.sin(r);
    // the groove: a thin S-curve along the long axis
    const groove = (px, py) => {
      const u = (px - x) * cs + (py - y) * sn, v = -(px - x) * sn + (py - y) * cs;
      return Math.abs(v - 2.2 * Math.sin(u / 4)) - 1.3;
    };
    c.fill(sub(ellipseR(x, y, 7, 10.5, deg + 90), groove), WHITE);
  };
  bean(32, 30, -30);
  bean(96, 94, 25);
  for (const [x, y, r] of [[96, 30, 4], [32, 94, 4], [64, 62, 3], [0, 62, 3], [64, 0, 3], [64, 128, 3], [128, 62, 3]]) c.fill(circle(x, y, r), WHITE);
  c.save('pat_beans');
}
{ // tablecloth under the board (slice9 36): wooden rim, linen cloth, stitched line
  const c = canvas(112, 112);
  c.fill(rbox(56, 56, 55, 55, 34), H('#c08a5c'));
  c.fill(rbox(56, 54, 51, 51, 30), H('#fdf8f0'));
  c.fill(sub(rbox(56, 54, 44, 44, 24), rbox(56, 54, 42, 42, 22)), H('#ead9c2'));
  c.save('cloth');
}
{ // gift box
  const c = canvas(112, 112);
  const box = rbox(56, 74, 38, 30, 7);
  const lid = rbox(56, 44, 45, 11, 7);
  const bow = union(ellipseR(40, 24, 15, 9, -25), ellipseR(72, 24, 15, 9, 25));
  c.parts([[bow, vgrad(H('#fff1a8'), H('#ffc93c'), 12, 36)], [box, vgrad(H('#5fc6b9'), H('#349a8d'), 46, 104)], [lid, vgrad(H('#7dd6cb'), H('#43ab9e'), 33, 55)]], 4);
  c.fill(rbox(56, 74, 8, 30, 2), H('#ffd23f'));
  c.fill(rbox(56, 44, 8, 11, 2), H('#ffe066'));
  c.fill(circle(56, 30, 7), H('#ffd23f'));
  c.fill(ellipseR(38, 40, 10, 3.5, -8), [1, 1, 1, 0.55]);
  c.fill(ellipseR(34, 66, 4, 12, 0), [1, 1, 1, 0.3]);
  c.save('gift');
}

// ======================================================================= CAFE DECOR
{ // wall patterns (white, tinted; tiled by the GUI)
  let c = canvas(64, 64);
  c.fill(rbox(16, 32, 8, 33, 0), [1, 1, 1, 1]);
  c.fill(rbox(48, 32, 2, 33, 0), [1, 1, 1, 1]);
  c.save('pat_stripes');
  c = canvas(64, 64);
  for (const [x, y] of [[16, 16], [48, 48]]) c.fill(circle(x, y, 7), WHITE);
  c.save('pat_dots');
  c = canvas(64, 64);
  c.fill(ring(32, 32, 0, 0), [0, 0, 0, 0]);
  c.fill((x, y) => Math.abs(Math.abs(x - 32) + Math.abs(y - 32) - 24) - 2.5, WHITE);
  c.fill(circle(32, 32, 4), WHITE);
  c.save('pat_diamond');
  c = canvas(64, 64);
  c.fill(rbox(16, 16, 16, 16, 0), WHITE);
  c.fill(rbox(48, 48, 16, 16, 0), WHITE);
  c.fill(rbox(48, 16, 16, 16, 0), [0.78, 0.78, 0.8, 1]);
  c.fill(rbox(16, 48, 16, 16, 0), [0.78, 0.78, 0.8, 1]);
  c.save('pat_checker');
  c = canvas(64, 64);
  c.fill(rbox(32, 32, 32, 32, 0), WHITE);
  for (const y of [0, 32]) c.fill(rbox(32, y, 32, 1.5, 0), [0.7, 0.7, 0.7, 1]);
  c.fill(rbox(20, 16, 1.5, 16, 0), [0.7, 0.7, 0.7, 1]);
  c.fill(rbox(52, 48, 1.5, 16, 0), [0.7, 0.7, 0.7, 1]);
  c.fill(ellipse(40, 14, 6, 2), [0.85, 0.85, 0.85, 1]);
  c.save('pat_planks');
}
{ // awning stripe segment (white + grey, tinted)
  const c = canvas(96, 64);
  const scallop = union(rbox(48, 22, 48, 22, 0), circle(24, 44, 24), circle(72, 44, 24));
  c.fill(inter(scallop, leftOf(48)), WHITE);
  c.fill(inter(scallop, rightOf(48)), [0.72, 0.72, 0.72, 1]);
  c.fill(rbox(48, 4, 48, 4, 0), [0.6, 0.6, 0.6, 1]);
  c.save('awning');
}
{ // window
  const c = canvas(160, 180);
  c.fill(rbox(80, 92, 74, 84, 14), OUTC);
  c.fill(rbox(80, 92, 70, 80, 12), H('#fffaf1'));
  c.fill(rbox(80, 88, 58, 68, 6), vgrad(H('#8fd3ff'), H('#d9f2ff'), 20, 156));
  c.fill(union(circle(54, 66, 14), circle(70, 58, 18), circle(88, 66, 13), rbox(70, 72, 30, 8, 8)), [1, 1, 1, 0.95]);
  c.fill(union(circle(110, 112, 10), circle(122, 106, 13), circle(134, 114, 9)), [1, 1, 1, 0.9]);
  c.fill(rbox(80, 88, 4, 68, 1), H('#fffaf1'));
  c.fill(rbox(80, 88, 58, 4, 1), H('#fffaf1'));
  c.fill(rbox(80, 164, 76, 8, 4), H('#e9d8bf'));
  c.save('window');
}
{ // pendant lamp
  const c = canvas(80, 140);
  c.fill(rbox(40, 34, 2, 34, 1), H('#3a2418'));
  const shade = poly([[8, 104], [72, 104], [56, 66], [24, 66]], 5);
  c.parts([[shade, vgrad(H('#4fa69c'), H('#2f7a72'), 66, 104)]], 3);
  c.fill(rbox(40, 101, 32, 3, 1.5), H('#ffd76a'));
  c.fill(rbox(40, 66, 10, 4, 2), H('#3a2418'));
  c.fill(circle(40, 110, 9), H('#fff1a8'));
  c.fill(ellipse(30, 80, 4, 10), [1, 1, 1, 0.3]);
  c.save('lamp');
}
{ // garland of lights
  const c = canvas(256, 64);
  const wire = [];
  for (let i = 0; i <= 32; i++) {
    const x = i * 8, y = 10 + Math.sin(i / 32 * Math.PI) * 26;
    wire.push([x, y]);
  }
  c.fill(polyline(wire, 1.6), H('#3a2418'));
  const cols = ['#ffd23f', '#ffb347', '#fff1a8', '#ffd23f', '#ffb347', '#fff1a8', '#ffd23f'];
  for (let i = 1; i < 8; i++) {
    const x = i * 32, y = 10 + Math.sin(x / 256 * Math.PI) * 26;
    c.fill(rbox(x, y + 4, 3, 3, 1), H('#3a2418'));
    c.fill(ellipse(x, y + 13, 6, 8.5), H(cols[i - 1]));
    c.fill(ellipse(x - 2, y + 10, 2, 3), [1, 1, 1, 0.6]);
  }
  c.save('garland');
}
{ // small potted plant
  const c = canvas(96, 110);
  const leaves = [ellipseR(30, 44, 10, 24, -35), ellipseR(66, 44, 10, 24, 35), ellipseR(48, 30, 10, 26, 0), ellipseR(20, 62, 8, 18, -70), ellipseR(76, 62, 8, 18, 70)];
  const pot = poly([[24, 66], [72, 66], [64, 106], [32, 106]], 4);
  c.parts([...leaves.map(l => [l, vgrad(H('#7ed957'), H('#3fa34d'), 10, 80)]), [pot, vgrad(H('#e9825a'), H('#c4603c'), 66, 106)]], 3.5);
  c.fill(rbox(48, 70, 26, 5, 2), H('#d36f48'));
  c.save('plant_small');
}
{ // big floor plant
  const c = canvas(140, 220);
  const leaves = [];
  const spec = [[70, 40, 16, 38, 0], [40, 60, 14, 34, -40], [100, 60, 14, 34, 40], [30, 100, 13, 30, -65], [110, 100, 13, 30, 65], [56, 86, 13, 32, -15], [86, 86, 13, 32, 15], [44, 126, 11, 26, -50], [96, 126, 11, 26, 50]];
  for (const [x, y, rx, ry, a] of spec) leaves.push(ellipseR(x, y, rx, ry, a));
  const pot = poly([[34, 150], [106, 150], [96, 214], [44, 214]], 6);
  c.parts([...leaves.map(l => [l, vgrad(H('#6cc644'), H('#2f8a3e'), 10, 150)]), [pot, vgrad(H('#f2f2f2'), H('#c9c9d1'), 150, 214)]], 4);
  for (const [x, y, rx, ry, a] of spec) {
    const r = (a - 90) * Math.PI / 180;
    c.fill(capsule(x - Math.cos(r) * ry * 0.8, y - Math.sin(r) * ry * 0.8, x + Math.cos(r) * ry * 0.8, y + Math.sin(r) * ry * 0.8, 1.2), [1, 1, 1, 0.35]);
  }
  c.fill(rbox(70, 156, 36, 5, 2), H('#9a9aa6'));
  c.save('plant_big');
}
{ // hanging plant
  const c = canvas(110, 150);
  c.fill(capsule(55, 0, 30, 60, 1.5), H('#7a5a3a'));
  c.fill(capsule(55, 0, 80, 60, 1.5), H('#7a5a3a'));
  const pot = inter(circle(55, 56, 28), below(56));
  const vines = [];
  for (const [x0, n] of [[34, 5], [55, 6], [76, 5]]) {
    for (let i = 0; i < n; i++) vines.push(ellipseR(x0 + (i % 2 ? 6 : -6), 76 + i * 13, 8, 6, i % 2 ? 30 : -30));
  }
  c.parts([...vines.map(v => [v, H('#5cb85c')]), [pot, vgrad(H('#ffd166'), H('#e9a93a'), 56, 84)]], 3);
  c.fill(union(ellipseR(40, 50, 10, 6, -30), ellipseR(70, 50, 10, 6, 30), ellipseR(55, 44, 7, 10, 0)), H('#7ed957'));
  c.save('plant_hang');
}
{ // coffee machine
  const c = canvas(130, 140);
  const body = rbox(65, 74, 52, 60, 12);
  const top = rbox(65, 18, 46, 8, 6);
  c.parts([[top, H('#e0a46c')], [body, vgrad(H('#e7e9ee'), H('#b9bec8'), 14, 134)]], 4);
  c.fill(rbox(65, 92, 40, 30, 8), H('#3a2f33'));
  c.fill(rbox(65, 70, 14, 6, 3), H('#c9c9d1'));
  c.fill(rbox(65, 104, 11, 12, 3), WHITE);
  c.fill(rbox(65, 118, 34, 4, 2), H('#c9c9d1'));
  for (const x of [40, 56, 72, 88]) c.fill(circle(x, 38, 5), x === 88 ? H('#7ed957') : H('#fff1a8'));
  c.fill(ellipse(34, 60, 4, 16), [1, 1, 1, 0.3]);
  c.save('coffee_machine');
}
{ // cake display
  const c = canvas(160, 130);
  const stand = union(rbox(80, 116, 50, 6, 3), rbox(80, 104, 8, 10, 2));
  const cake = union(rbox(80, 76, 38, 20, 6));
  c.parts([[stand, H('#c9c9d1')], [cake, H('#f7d59c')]], 4);
  c.fill(rbox(80, 62, 38, 7, 6), H('#ff9fbd'));
  c.fill(rbox(80, 80, 38, 3, 0), H('#ff7a8a'));
  for (const x of [54, 72, 90, 108]) c.fill(circle(x, 52, 5), H('#ff4d5e'));
  c.fill(sub(inter(ellipse(80, 96, 66, 92), above(96)), inter(ellipse(80, 96, 62, 88), above(96))), [1, 1, 1, 0.9]);
  c.fill(inter(ellipse(80, 96, 62, 88), above(96)), [0.85, 0.95, 1, 0.25]);
  c.fill(ellipseR(40, 40, 6, 22, 20), [1, 1, 1, 0.4]);
  c.save('cake_display');
}
{ // chalk menu board
  const c = canvas(150, 120);
  c.fill(rbox(75, 60, 72, 56, 10), OUTC);
  c.fill(rbox(75, 60, 68, 52, 8), H('#b8763f'));
  c.fill(rbox(75, 60, 58, 42, 4), H('#2f4a3c'));
  const chalk = [1, 1, 1, 0.85];
  for (const [y, w] of [[34, 40], [50, 30], [66, 36], [82, 24]]) c.fill(capsule(48, y, 48 + w, y, 2.2), chalk);
  c.fill(circle(34, 34, 4), chalk);
  c.fill(circle(34, 50, 4), chalk);
  c.fill(circle(34, 66, 4), chalk);
  c.fill(circle(34, 82, 4), chalk);
  c.fill(sub(rbox(112, 62, 10, 12, 4), rbox(112, 60, 7, 11, 3)), chalk);
  c.fill(inter(ring(124, 62, 5, 3), rightOf(122)), chalk);
  c.save('menu_board');
}
{ // table with two chairs
  const c = canvas(180, 130);
  const chairL = union(rbox(26, 70, 8, 34, 4), rbox(36, 92, 18, 5, 3), rbox(24, 114, 3, 16, 1), rbox(48, 114, 3, 16, 1));
  const chairR = union(rbox(154, 70, 8, 34, 4), rbox(144, 92, 18, 5, 3), rbox(156, 114, 3, 16, 1), rbox(132, 114, 3, 16, 1));
  const top = ellipse(90, 60, 54, 12);
  const leg = union(rbox(90, 92, 5, 30, 2), ellipse(90, 122, 24, 6));
  c.parts([[chairL, H('#c98a57')], [chairR, H('#c98a57')], [leg, H('#5b4636')], [top, H('#fffaf1')]], 3.5);
  c.fill(ellipse(90, 57, 46, 7), [1, 1, 1, 0.6]);
  c.fill(rbox(82, 46, 7, 9, 3), H('#ffffff'));
  c.fill(ellipse(82, 38, 7, 2.5), H('#7a4422'));
  c.save('table');
}

{ // flower vase (decor "flowers" tier 1)
  const c = canvas(96, 124);
  const vase = union(ellipse(48, 96, 22, 22), rbox(48, 72, 10, 10, 4));
  const leaves = [ellipseR(30, 58, 6, 16, -40), ellipseR(66, 58, 6, 16, 40), ellipseR(48, 50, 5, 14, 0)];
  const blooms = [[48, 30, '#ff7a5c'], [28, 42, '#ffd23f'], [68, 40, '#8cc4ff'], [40, 20, '#fff6e8'], [60, 22, '#ff9f43']];
  c.parts([...leaves.map(l => [l, H('#6cc98a')]), ...blooms.map(([x, y, col]) => [circle(x, y, 11), H(col)]), [vase, vgrad(H('#a7e8d6'), H('#5fc4ab'), 66, 118)]], 3.5);
  for (const [x, y, col] of blooms) {
    for (let k = 0; k < 5; k++) {
      const a = k * Math.PI * 2 / 5;
      c.fill(circle(x + Math.cos(a) * 5, y + Math.sin(a) * 5, 4.2), lighter(H(col), 0.25));
    }
    c.fill(circle(x, y, 3.2), H('#ffe27a'));
  }
  c.fill(ellipseR(38, 92, 4, 11, 10), [1, 1, 1, 0.45]);
  c.save('vase');
}
{ // window flower box (tier 2)
  const c = canvas(176, 64);
  const box = rbox(88, 46, 80, 15, 6);
  const blooms = [];
  for (let i = 0; i < 9; i++) blooms.push([20 + i * 17, 22 + (i % 2) * 7, ['#ff7a5c', '#fff6e8', '#8cc4ff', '#ffd23f'][i % 4]]);
  const leaves = blooms.map(([x, y], i) => ellipseR(x + (i % 2 ? 6 : -6), y + 10, 6, 10, i % 2 ? 35 : -35));
  c.parts([...leaves.map(l => [l, H('#6cc98a')]), ...blooms.map(([x, y, col]) => [circle(x, y, 8.5), H(col)]), [box, vgrad(H('#d39b6a'), H('#a86c40'), 31, 61)]], 3);
  for (const [x, y] of blooms) c.fill(circle(x, y, 3), H('#ffe27a'));
  c.fill(rbox(88, 40, 74, 2, 1), [1, 1, 1, 0.45]);
  c.save('flower_box');
}
{ // hanging flower garland (tier 3, tiled along the awning)
  const c = canvas(256, 64);
  const wire = [];
  for (let i = 0; i <= 32; i++) wire.push([i * 8, 8 + Math.sin(i / 32 * Math.PI) * 22]);
  c.fill(polyline(wire, 1.8), H('#5fae74'));
  const cols = ['#ff7a5c', '#fff6e8', '#8cc4ff', '#ffd23f', '#ff9f43', '#ffe27a', '#b8e0ff'];
  for (let i = 0; i < 8; i++) {
    const x = 16 + i * 32, y = 8 + Math.sin(x / 256 * Math.PI) * 22;
    c.fill(ellipseR(x - 9, y + 4, 4, 8, -50), H('#6cc98a'));
    c.fill(ellipseR(x + 9, y + 4, 4, 8, 50), H('#6cc98a'));
    for (let k = 0; k < 5; k++) {
      const a = k * Math.PI * 2 / 5 - Math.PI / 2;
      c.fill(circle(x + Math.cos(a) * 5.5, y + 8 + Math.sin(a) * 5.5, 5), H(cols[i % cols.length]));
    }
    c.fill(circle(x, y + 8, 3.4), H('#ffe27a'));
  }
  c.save('flower_garland');
}

// ======================================================================= atlas + preview
const images = ALL.map(a => `images {\n  image: "/${OUT}/${a.name}.png"\n}\n`).join('');
fs.writeFileSync(ATLAS, images + 'margin: 2\nextrude_borders: 2\ninner_padding: 0\n');
// sprite sizes for the GUI (aspect-correct icons)
fs.writeFileSync('main/gui/sprite_sizes.lua', '-- generated by tools/gen_sprites.js\nreturn {\n' +
  ALL.map(a => `\t${a.name} = { ${a.w}, ${a.h} },\n`).join('') + '}\n');
console.log(`sprites: ${ALL.length}, pixels: ${ALL.reduce((s, a) => s + a.w * a.h, 0)}`);

if (PREVIEW) {
  const W = 1200, pad = 8;
  let x = pad, y = pad, rowH = 0;
  const placed = [];
  for (const a of ALL) {
    if (x + a.w > W) { x = pad; y += rowH + pad; rowH = 0; }
    placed.push([a, x, y]);
    x += a.w + pad; rowH = Math.max(rowH, a.h);
  }
  const Hh = y + rowH + pad;
  const px = new Float32Array(W * Hh * 4);
  for (let i = 0; i < W * Hh; i++) {
    const cx = (i % W) >> 4, cy = Math.floor(i / W) >> 4;
    const v = (cx + cy) % 2 ? 0.55 : 0.45;
    px[i * 4] = v * 1.1; px[i * 4 + 1] = v; px[i * 4 + 2] = v * 0.9; px[i * 4 + 3] = 1;
  }
  for (const [a, ox, oy] of placed) {
    for (let j = 0; j < a.h; j++) for (let i = 0; i < a.w; i++) {
      const s = (j * a.w + i) * 4, d = ((oy + j) * W + ox + i) * 4, al = a.px[s + 3];
      for (let k = 0; k < 3; k++) px[d + k] = a.px[s + k] * al + px[d + k] * (1 - al);
    }
  }
  fs.writeFileSync(PREVIEW, encodePNG(W, Hh, px));
}
