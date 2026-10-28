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
const OUTC = H('#4a2a1a');
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

// ======================================================================= FOOD (112x112)
const S = 112;
{ // burger
  const c = canvas(S, S);
  const topBun = union(inter(ellipse(56, 52, 43, 35), above(52)), rbox(56, 49, 43, 6, 6));
  const lettuce = union(...[16, 24, 32, 40, 48, 56, 64, 72, 80, 88, 96].map(x => circle(x, 58, 6)));
  const cheese = union(rbox(56, 61, 42, 3.5, 2), poly([[28, 62], [40, 62], [34, 72]], 1.5), poly([[66, 62], [78, 62], [72, 73]], 1.5));
  const patty = rbox(56, 69, 42, 7.5, 7);
  const bottom = rbox(56, 85, 40, 10, 9);
  c.parts([[bottom, vgrad(H('#f2ad55'), H('#d98a32'), 76, 95)], [patty, H('#6e3b20')], [cheese, H('#ffc93c')],
    [lettuce, H('#6cc644')], [topBun, vgrad(H('#f7b75e'), H('#e08d34'), 18, 56)]], 4);
  for (const [x, y] of [[40, 32], [56, 26], [72, 32], [47, 42], [65, 42]]) c.fill(ellipseR(x, y, 3.4, 2, x < 56 ? -20 : 20), H('#fff4d8'));
  c.fill(ellipse(40, 30, 9, 4.5), SHINE);
  c.save('food_burger');
}
{ // coffee
  const c = canvas(S, S);
  const saucer = ellipse(56, 94, 46, 10);
  const body = poly([[20, 42], [86, 42], [77, 90], [29, 90]], 7);
  const handle = inter(ring(86, 62, 12, 8), rightOf(80));
  c.parts([[saucer, H('#f4f4f8')], [handle, H('#ffffff')], [body, vgrad(H('#ffffff'), H('#e3e6ef'), 40, 92)]], 4);
  c.fill(inter(body, rbox(53, 66, 60, 5.5, 0)), H('#ff8fa3'));
  c.fill(ellipse(53, 44, 30, 7), H('#7a4422'));
  c.fill(ellipse(48, 43, 14, 3), H('#c98b5a'));
  c.fill(capsule(42, 30, 38, 12, 3.5), [1, 1, 1, 0.75]);
  c.fill(capsule(62, 30, 66, 10, 3.5), [1, 1, 1, 0.75]);
  c.fill(ellipse(32, 60, 4, 12), [1, 1, 1, 0.6]);
  c.save('food_coffee');
}
{ // donut
  const c = canvas(S, S);
  const dough = sub(circle(56, 58, 45), circle(56, 58, 14));
  const wav = (x, y) => len(x - 56, y - 55) - 38 - 3 * Math.sin(Math.atan2(y - 55, x - 56) * 7);
  const icing = sub(wav, circle(56, 56, 17.5));
  c.parts([[dough, vgrad(H('#eeb065'), H('#c98236'), 14, 104)]], 4);
  c.fill(grow(icing, 0), H('#ff7eb6'));
  c.fill(ring(56, 56, 18, 3), H('#d95c95'));
  const cols = [H('#ffffff'), H('#ffe066'), H('#5ec3ff'), H('#7ed957'), H('#9b8cff')];
  const sprinkles = [[34, 36, 30], [50, 26, -40], [70, 30, 60], [82, 46, 10], [80, 68, -50], [64, 82, 30], [42, 80, -20], [28, 62, 70], [30, 48, -60], [86, 58, 80], [52, 88, 0], [74, 80, 45]];
  sprinkles.forEach(([x, y, a], i) => {
    const r = a * Math.PI / 180;
    c.fill(capsule(x - Math.cos(r) * 4, y - Math.sin(r) * 4, x + Math.cos(r) * 4, y + Math.sin(r) * 4, 2), cols[i % cols.length]);
  });
  c.fill(ellipseR(36, 34, 10, 4, -35), SHINE);
  c.save('food_donut');
}
{ // pizza
  const c = canvas(S, S);
  const cheese = poly([[56, 106], [14, 28], [98, 28]], 5);
  const crust = capsule(14, 24, 98, 24, 11);
  c.parts([[cheese, vgrad(H('#ffe07a'), H('#ffc53d'), 20, 106)], [crust, vgrad(H('#f0b261'), H('#d48a3a'), 14, 34)]], 4);
  for (const [x, y, r] of [[56, 50, 9], [40, 40, 7], [72, 40, 7], [56, 76, 7]]) {
    c.fill(circle(x, y, r), H('#d8432f'));
    c.fill(circle(x - r * 0.3, y - r * 0.3, r * 0.35), [1, 1, 1, 0.3]);
  }
  c.fill(ellipseR(68, 60, 5, 2.5, -40), H('#3fa34d'));
  c.fill(ellipseR(46, 62, 5, 2.5, 30), H('#3fa34d'));
  c.fill(capsule(26, 20, 86, 20, 3), [1, 1, 1, 0.35]);
  c.save('food_pizza');
}
{ // cupcake
  const c = canvas(S, S);
  const wrap = poly([[24, 64], [88, 64], [79, 106], [33, 106]], 4);
  const frost = union(circle(32, 62, 14), circle(80, 62, 14), circle(56, 58, 24), circle(44, 44, 16), circle(68, 44, 16), circle(56, 30, 14));
  const cherry = circle(58, 16, 8);
  c.parts([[wrap, H('#4fb6f2')], [frost, vgrad(H('#fff0f6'), H('#ffc2dc'), 16, 76)], [cherry, H('#e63946')]], 4);
  c.fill(inter(wrap, (x, y) => Math.abs(((x - 56 + 1000) % 12) - 6) - 2), H('#2f93d6'));
  c.fill(capsule(60, 9, 68, 2, 1.6), H('#4a2a1a'));
  c.fill(circle(55, 13, 2.5), SHINE);
  c.fill(ellipseR(42, 40, 8, 4, -30), [1, 1, 1, 0.6]);
  c.save('food_cupcake');
}
{ // fries
  const c = canvas(S, S);
  const sticks = union(capsule(34, 60, 30, 18, 5.5), capsule(46, 60, 44, 10, 5.5), capsule(58, 60, 58, 14, 5.5), capsule(70, 60, 72, 8, 5.5), capsule(80, 60, 86, 20, 5.5));
  const box = poly([[24, 50], [88, 50], [78, 106], [34, 106]], 5);
  c.parts([[sticks, vgrad(H('#ffe27a'), H('#ffc53d'), 8, 60)], [box, vgrad(H('#f25c4f'), H('#d23a30'), 50, 106)]], 4);
  c.fill(circle(56, 78, 11), H('#ffd34e'));
  c.fill(star(56, 78, 8, 3.5), H('#f25c4f'));
  c.fill(capsule(30, 56, 82, 56, 2.2), [1, 1, 1, 0.35]);
  c.save('food_fries');
}
{ // ice cream
  const c = canvas(S, S);
  const cone = poly([[32, 60], [80, 60], [56, 108]], 4);
  const scoop1 = union(circle(56, 52, 26), circle(36, 62, 9), circle(52, 66, 9), circle(70, 64, 9));
  const scoop2 = circle(56, 30, 19);
  const cherry = circle(62, 11, 6.5);
  c.parts([[cone, H('#e9ab5e')], [scoop1, vgrad(H('#ffc0d9'), H('#ff8fb8'), 26, 74)], [scoop2, vgrad(H('#c8f2dc'), H('#8fdcb6'), 11, 48)], [cherry, H('#e63946')]], 4);
  c.fill(inter(cone, (x, y) => Math.min(Math.abs(((x + y) % 12) - 6), Math.abs(((x - y + 1200) % 12) - 6)) - 1.2, below(70)), H('#c98636'));
  c.fill(ellipseR(44, 44, 7, 4, -30), SHINE);
  c.fill(ellipseR(48, 24, 5, 3, -30), SHINE);
  c.save('food_icecream');
}
{ // hot dog
  const c = canvas(S, S);
  const back = capsule(18, 60, 94, 60, 21);
  const sausage = capsule(10, 52, 102, 52, 11);
  const front = inter(capsule(18, 66, 94, 66, 19), below(60));
  c.parts([[back, H('#e7a24d')], [sausage, vgrad(H('#e0705a'), H('#b9472f'), 40, 64)], [front, vgrad(H('#f7c070'), H('#e39b45'), 60, 86)]], 4);
  const zig = [];
  for (let i = 0; i <= 10; i++) zig.push([20 + i * 7.2, i % 2 ? 44 : 52]);
  c.fill(polyline(zig, 2.4), H('#ffd23f'));
  c.fill(capsule(26, 76, 86, 76, 2.5), [1, 1, 1, 0.3]);
  c.save('food_hotdog');
}
{ // croissant
  const c = canvas(S, S);
  const segs = [[-166, 8, 12], [-128, 12, 18], [-90, 14, 22], [-52, 12, 18], [-14, 8, 12]];
  const shapes = segs.map(([a, rx, ry]) => {
    const r = a * Math.PI / 180;
    return ellipseR(56 + Math.cos(r) * 40, 90 + Math.sin(r) * 40, rx, ry, a + 90);
  });
  c.fill(grow(union(...shapes), 4), OUTC);
  for (const i of [0, 4, 1, 3, 2]) {
    c.fill(grow(shapes[i], 1.5), darker(H('#c97a2c'), 0.9));
    c.fill(shapes[i], vgrad(H('#f7c26b'), H('#d98c36'), 40, 96));
  }
  c.fill(ellipseR(50, 52, 8, 3.5, -10), SHINE);
  c.save('food_croissant');
}
{ // cookie
  const c = canvas(S, S);
  const body = sub(circle(56, 58, 44), union(circle(98, 22, 14), circle(86, 12, 10)));
  c.parts([[body, vgrad(H('#e8b06a'), H('#c98a45'), 14, 102)]], 4);
  for (const [x, y, rx, ry] of [[40, 40, 6, 5], [62, 34, 5, 4], [36, 66, 6, 5], [58, 58, 7, 5], [78, 62, 5, 5], [52, 82, 6, 5], [74, 84, 5, 4], [28, 50, 4, 3]]) {
    c.fill(ellipse(x, y, rx, ry), H('#5a3420'));
  }
  c.fill(ellipseR(36, 30, 10, 4, -35), [1, 1, 1, 0.3]);
  c.save('food_cookie');
}
{ // juice
  const c = canvas(S, S);
  const glass = poly([[30, 32], [82, 32], [76, 104], [36, 104]], 6);
  const straw = capsule(66, 46, 84, 6, 4.5);
  const slice = inter(circle(32, 34, 17), above(36));
  c.parts([[straw, H('#ff5a6e')], [glass, H('#e6f6ff')], [slice, H('#ff9f1c')]], 4);
  c.fill(inter(grow(glass, -5), below(46)), vgrad(H('#ffc04d'), H('#ff8c1a'), 46, 104));
  c.fill(inter(circle(32, 34, 12), above(34)), H('#ffd27a'));
  for (const a of [-150, -120, -90, -60, -30]) {
    const r = a * Math.PI / 180;
    c.fill(capsule(32, 34, 32 + Math.cos(r) * 11, 34 + Math.sin(r) * 11, 1), H('#ff9f1c'));
  }
  c.fill(capsule(42, 52, 40, 94, 3), [1, 1, 1, 0.55]);
  c.save('food_juice');
}
{ // cake slice
  const c = canvas(S, S);
  const body = rbox(56, 76, 42, 26, 5);
  const icing = union(rbox(56, 50, 43, 8, 7), circle(26, 58, 5), circle(48, 60, 5), circle(74, 59, 5), circle(90, 57, 4));
  const berry = union(circle(51, 30, 8), circle(61, 30, 8), poly([[44, 32], [68, 32], [56, 46]], 2));
  c.parts([[body, H('#f7d59c')], [icing, H('#ff9fbd')], [berry, H('#ff4d5e')]], 4);
  c.fill(rbox(56, 76, 42, 3.5, 0), H('#ffffff'));
  c.fill(rbox(56, 90, 42, 3.5, 0), H('#ff7a8a'));
  c.fill(poly([[50, 22], [56, 16], [62, 22], [56, 26]], 1), H('#3fa34d'));
  c.fill(ellipse(36, 48, 8, 3), SHINE);
  c.save('food_cake');
}
{ // taco
  const c = canvas(S, S);
  const fill = union(...[-170, -150, -130, -110, -90, -70, -50, -30, -10].map((a, i) => {
    const r = a * Math.PI / 180;
    return circle(56 + Math.cos(r) * 44, 92 + Math.sin(r) * 44, i % 2 ? 9 : 8);
  }));
  const shell = inter(circle(56, 92, 44), above(92));
  c.parts([[fill, H('#6cc644')], [shell, vgrad(H('#ffd469'), H('#e9a93a'), 48, 92)]], 4);
  for (const a of [-160, -120, -80, -40]) {
    const r = a * Math.PI / 180;
    c.fill(circle(56 + Math.cos(r) * 46, 92 + Math.sin(r) * 46, 5), H('#e63946'));
  }
  for (const [x, y] of [[40, 70], [64, 64], [76, 80], [50, 84], [30, 84]]) c.fill(circle(x, y, 2.5), H('#d99a2b'));
  c.save('food_taco');
}
{ // sushi
  const c = canvas(S, S);
  const nori = circle(56, 58, 42);
  c.parts([[nori, H('#24332a')]], 4);
  c.fill(circle(56, 56, 34), H('#fbfbf7'));
  c.fill(circle(56, 56, 15), H('#ff8a65'));
  c.fill(capsule(50, 50, 60, 60, 2), H('#ffb59c'));
  for (const [x, y] of [[38, 42], [74, 44], [76, 70], [40, 72], [56, 82]]) c.fill(ellipse(x, y, 4, 3), H('#7ed957'));
  c.fill(ellipseR(34, 32, 9, 4, -40), [1, 1, 1, 0.25]);
  c.save('food_sushi');
}
{ // egg
  const c = canvas(S, S);
  const white = union(circle(56, 58, 30), circle(36, 48, 20), circle(76, 44, 22), circle(74, 74, 20), circle(38, 74, 18));
  c.parts([[white, H('#ffffff')]], 4);
  c.fill(circle(58, 58, 17), H('#e8a91c'));
  c.fill(circle(58, 56, 16), H('#ffc12e'));
  c.fill(ellipse(52, 50, 6, 4), [1, 1, 1, 0.7]);
  c.save('food_egg');
}
{ // cheese
  const c = canvas(S, S);
  const front = poly([[14, 62], [98, 62], [98, 98], [14, 98]], 3);
  const top = poly([[14, 62], [74, 26], [98, 62]], 3);
  c.parts([[front, H('#ffcf3f')], [top, H('#ffe07a')]], 4);
  for (const [x, y, r] of [[34, 80, 7], [60, 74, 5], [80, 86, 8], [52, 92, 4], [70, 48, 5], [86, 56, 3]]) c.fill(circle(x, y, r), H('#e8b324'));
  c.save('food_cheese');
}

// ======================================================================= TILE
{
  const c = canvas(112, 124);
  const face = rbox(56, 54, 52, 52, 16);
  const side = rbox(56, 64, 52, 56, 16);
  c.parts([[side, vgrad(H('#efc79b'), H('#d9a46f'), 60, 120)], [face, vgrad(H('#fffaf1'), H('#f7ead6'), 4, 106)]], 3.5);
  c.fill(sub(face, rbox(56, 54, 47, 47, 13)), [1, 1, 1, 0.55]);
  c.save('tile');
}
{
  const c = canvas(128, 140);
  c.soft((x, y) => {
    const d = rbox(64, 70, 54, 60, 18)(x, y);
    return d < 0 ? 1 : 1 - d / 9;
  }, [1, 1, 1]);
  c.save('tile_glow');
}

// ======================================================================= CUSTOMERS (160x160)
function customer(name, fur, shirt, extra) {
  const c = canvas(160, 160);
  const body = rbox(80, 152, 58, 34, 28);
  const head = circle(80, 84, 46);
  const parts = extra.back ? extra.back() : [];
  c.parts([...parts, [body, shirt], [head, fur]], 4);
  c.fill(inter(body, below(140)), darker(shirt, 0.88));
  c.fill(capsule(66, 130, 80, 140, 3), [1, 1, 1, 0.5]);
  c.fill(capsule(94, 130, 80, 140, 3), [1, 1, 1, 0.5]);
  if (extra.face) extra.face(c);
  // eyes
  const ey = extra.eyeY || 80;
  for (const x of [62, 98]) {
    c.fill(circle(x, ey, 6.5), H('#2b1d16'));
    c.fill(circle(x + 2, ey - 2.5, 2.2), WHITE);
  }
  c.fill(ellipse(54, ey + 15, 8, 5), H('#ff7a8a', 0.45));
  c.fill(ellipse(106, ey + 15, 8, 5), H('#ff7a8a', 0.45));
  if (!extra.noMouth) c.fill(inter(ring(80, ey + 14, 8, 3.4), below(ey + 14)), H('#2b1d16'));
  if (extra.top) extra.top(c);
  c.fill(ellipseR(60, 52, 12, 6, -30), [1, 1, 1, 0.25]);
  c.save('cust_' + name);
}
customer('cat', H('#f6a55a'), H('#5ec3ff'), {
  back: () => [[poly([[38, 62], [44, 16], [74, 44]], 4), H('#f6a55a')], [poly([[122, 62], [116, 16], [86, 44]], 4), H('#f6a55a')]],
  face: c => {
    c.fill(poly([[46, 50], [48, 28], [64, 44]], 2), H('#ffb3c1'));
    c.fill(poly([[114, 50], [112, 28], [96, 44]], 2), H('#ffb3c1'));
    for (const x of [70, 80, 90]) c.fill(capsule(x, 42, x, 54, 3), H('#e0853a'));
    c.fill(poly([[74, 88], [86, 88], [80, 95]], 1.5), H('#ff7a8a'));
    for (const s of [-1, 1]) {
      c.fill(capsule(80 + s * 24, 96, 80 + s * 44, 92, 1.2), H('#4a2a1a'));
      c.fill(capsule(80 + s * 24, 100, 80 + s * 44, 102, 1.2), H('#4a2a1a'));
    }
  },
});
customer('bear', H('#a8724a'), H('#7ed957'), {
  back: () => [[circle(42, 46, 17), H('#a8724a')], [circle(118, 46, 17), H('#a8724a')]],
  face: c => {
    c.fill(circle(42, 46, 9), H('#e3b48a'));
    c.fill(circle(118, 46, 9), H('#e3b48a'));
    c.fill(ellipse(80, 102, 22, 16), H('#e8c8a0'));
    c.fill(ellipse(80, 92, 8, 5.5), H('#3a2418'));
  },
});
customer('bunny', H('#f4f0f0'), H('#ff9fbd'), {
  back: () => [[capsule(62, 48, 54, 8, 13), H('#f4f0f0')], [capsule(98, 48, 106, 8, 13), H('#f4f0f0')]],
  face: c => {
    c.fill(capsule(62, 44, 55, 14, 6), H('#ffb3c1'));
    c.fill(capsule(98, 44, 105, 14, 6), H('#ffb3c1'));
    c.fill(ellipse(80, 92, 6, 4.5), H('#ff7a8a'));
    c.fill(rbox(80, 108, 6, 5, 2), WHITE);
  },
});
customer('panda', H('#fafafa'), H('#ffcf4a'), {
  back: () => [[circle(42, 46, 16), H('#2b2b33')], [circle(118, 46, 16), H('#2b2b33')]],
  face: c => {
    c.fill(ellipseR(60, 82, 15, 11, -25), H('#2b2b33'));
    c.fill(ellipseR(100, 82, 15, 11, 25), H('#2b2b33'));
    c.fill(ellipse(80, 93, 7, 5), H('#2b2b33'));
  },
});
customer('fox', H('#ff8a3d'), H('#9b8cff'), {
  back: () => [[poly([[36, 66], [40, 12], [76, 42]], 4), H('#ff8a3d')], [poly([[124, 66], [120, 12], [84, 42]], 4), H('#ff8a3d')]],
  face: c => {
    c.fill(poly([[42, 30], [41, 14], [54, 26]], 2), H('#3a2418'));
    c.fill(poly([[118, 30], [119, 14], [106, 26]], 2), H('#3a2418'));
    c.fill(union(ellipse(58, 104, 24, 18), ellipse(102, 104, 24, 18), ellipse(80, 110, 18, 16)), H('#fff3e6'));
    c.fill(ellipse(80, 96, 7, 5), H('#2b1d16'));
  },
});
customer('frog', H('#7ccf5a'), H('#ff8a65'), {
  back: () => [[circle(54, 46, 20), H('#7ccf5a')], [circle(106, 46, 20), H('#7ccf5a')]],
  eyeY: 46,
  noMouth: true,
  face: c => {
    c.fill(circle(54, 46, 13), WHITE);
    c.fill(circle(106, 46, 13), WHITE);
    c.fill(inter(ring(80, 88, 26, 4), below(90)), H('#2b1d16'));
    c.fill(ellipse(54, 106, 8, 5), H('#ff7a8a', 0.45));
    c.fill(ellipse(106, 106, 8, 5), H('#ff7a8a', 0.45));
  },
});
customer('pig', H('#ffb3c1'), H('#4fd1c5'), {
  back: () => [[poly([[40, 56], [46, 28], [70, 44]], 5), H('#ffb3c1')], [poly([[120, 56], [114, 28], [90, 44]], 5), H('#ffb3c1')]],
  face: c => {
    c.fill(ellipse(80, 98, 17, 12), H('#ff8fa6'));
    c.fill(ellipse(74, 98, 3.5, 5), H('#c75b74'));
    c.fill(ellipse(86, 98, 3.5, 5), H('#c75b74'));
  },
  noMouth: true,
});
customer('penguin', H('#34495e'), H('#ffd166'), {
  face: c => {
    c.fill(union(circle(64, 88, 25), circle(96, 88, 25), ellipse(80, 108, 26, 18)), H('#fafafa'));
    c.fill(poly([[70, 94], [90, 94], [80, 106]], 3), H('#ff9f1c'));
  },
  noMouth: true,
});

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
{ // soft round shadow
  const c = canvas(96, 40);
  c.soft((x, y) => 1 - len((x - 48) / 46, (y - 20) / 18), [0, 0, 0]);
  c.save('shadow');
}

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
icon('plus', c => { c.fill(capsule(48, 18, 48, 78, 9), WHITE); c.fill(capsule(18, 48, 78, 48, 9), WHITE); });
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
icon('star', c => c.fill(star(48, 52, 44, 20, 5, -90, 3), WHITE));
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
icon('lock', c => {
  c.fill(inter(ring(48, 40, 20, 9), above(44)), WHITE);
  c.fill(rbox(48, 64, 30, 24, 8), WHITE);
});
icon('arrow', c => c.fill(union(rbox(40, 48, 26, 10, 4), poly([[56, 20], [88, 48], [56, 76]], 4)), WHITE));

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
{ // angry face
  const c = canvas(64, 64);
  c.parts([[circle(32, 32, 27), vgrad(H('#ff7a5a'), H('#e63946'), 4, 60)]], 3);
  c.fill(capsule(14, 20, 27, 27, 3), H('#4a1a1a'));
  c.fill(capsule(50, 20, 37, 27, 3), H('#4a1a1a'));
  c.fill(circle(22, 32, 4), H('#4a1a1a'));
  c.fill(circle(42, 32, 4), H('#4a1a1a'));
  c.fill(inter(ring(32, 52, 10, 4), above(48)), H('#4a1a1a'));
  c.save('angry');
}
{ // trash bin
  const c = canvas(112, 112);
  const lid = union(rbox(56, 22, 40, 7, 5), rbox(56, 13, 12, 5, 4));
  const body = poly([[22, 32], [90, 32], [82, 104], [30, 104]], 6);
  c.parts([[body, vgrad(H('#8fd6c1'), H('#4fb39a'), 32, 104)], [lid, H('#6cc4ab')]], 4);
  for (const x of [40, 56, 72]) c.fill(capsule(x, 44, x + (x - 56) * 0.08, 92, 3.5), H('#3e9a82'));
  c.fill(rbox(56, 22, 32, 2, 1), [1, 1, 1, 0.4]);
  c.save('bin');
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
  c.parts([[shade, vgrad(H('#2a9d8f'), H('#1d7268'), 66, 104)]], 3);
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
  const cols = ['#ff5a6e', '#ffd23f', '#5ec3ff', '#7ed957', '#ff9f1c', '#9b8cff', '#ff7eb6'];
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
  c.parts([[top, H('#c9c9d1')], [body, vgrad(H('#ff6b6b'), H('#d64545'), 14, 134)]], 4);
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
  c.parts([[chairL, H('#ff9f1c')], [chairR, H('#ff9f1c')], [leg, H('#5a4a44')], [top, H('#fffaf1')]], 3.5);
  c.fill(ellipse(90, 57, 46, 7), [1, 1, 1, 0.6]);
  c.fill(rbox(82, 46, 7, 9, 3), H('#ffffff'));
  c.fill(ellipse(82, 38, 7, 2.5), H('#7a4422'));
  c.save('table');
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
