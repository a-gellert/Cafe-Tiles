// Procedural sound effects and the looping cafe tune (16-bit mono WAV).
// usage (from the project root): node tools/gen_sounds.js
const fs = require('fs');
const path = require('path');

const OUT = 'main/assets/sounds';
fs.mkdirSync(OUT, { recursive: true });

function writeWav(name, samples, rate) {
  const data = Buffer.alloc(samples.length * 2);
  for (let i = 0; i < samples.length; i++) {
    data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, samples[i])) * 32767), i * 2);
  }
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + data.length, 4); h.write('WAVE', 8);
  h.write('fmt ', 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22);
  h.writeUInt32LE(rate, 24); h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34);
  h.write('data', 36); h.writeUInt32LE(data.length, 40);
  fs.writeFileSync(path.join(OUT, name + '.wav'), Buffer.concat([h, data]));
  return data.length + 44;
}

// deterministic noise
let seed = 12345;
const noise = () => { seed = (seed * 16807) % 2147483647; return seed / 1073741823.5 - 1; };
const TAU = Math.PI * 2;
const note = n => 440 * Math.pow(2, (n - 69) / 12);   // MIDI -> Hz

function render(dur, rate, fn) {
  const n = Math.floor(dur * rate), out = new Float32Array(n);
  for (let i = 0; i < n; i++) out[i] = fn(i / rate, i);
  return out;
}
function normalize(buf, peak = 0.8) {
  let m = 0;
  for (const v of buf) m = Math.max(m, Math.abs(v));
  if (m > 0) for (let i = 0; i < buf.length; i++) buf[i] *= peak / m;
  return buf;
}
// short fade in/out against clicks
function fade(buf, rate, ms = 4) {
  const k = Math.floor(rate * ms / 1000);
  for (let i = 0; i < k && i < buf.length; i++) {
    buf[i] *= i / k;
    buf[buf.length - 1 - i] *= i / k;
  }
  return buf;
}

const SFX = 22050;
let total = 0;
function sfx(name, dur, fn, peak = 0.8) {
  total += writeWav(name, fade(normalize(render(dur, SFX, fn), peak), SFX), SFX);
}

// bell-like partials with exponential decay
const bell = (t, f, decay, partials = [[1, 1], [2, 0.4], [3, 0.2]]) =>
  partials.reduce((s, [m, a]) => s + a * Math.sin(TAU * f * m * t), 0) * Math.exp(-t * decay);

sfx('tap', 0.09, t => Math.sin(TAU * (520 * t + 2600 * t * t)) * Math.exp(-t * 45), 0.6);
sfx('place', 0.08, t => (Math.sin(TAU * 260 * t) * 0.7 + noise() * 0.3 * Math.exp(-t * 120)) * Math.exp(-t * 55), 0.55);
sfx('blocked', 0.12, t => Math.sin(TAU * 150 * t) * Math.exp(-t * 35) + Math.sin(TAU * 110 * t) * 0.5 * Math.exp(-t * 30), 0.5);
sfx('button', 0.06, t => Math.sin(TAU * 1100 * t) * Math.exp(-t * 70) + noise() * 0.15 * Math.exp(-t * 200), 0.5);
sfx('match', 0.45, t => {
  const ns = [84, 88, 91];
  let s = 0;
  ns.forEach((n, i) => { const tt = t - i * 0.06; if (tt > 0) s += bell(tt, note(n), 9); });
  return s;
}, 0.7);
sfx('serve', 0.55, t => {
  let s = noise() * 0.25 * Math.exp(-t * 60);
  if (t > 0.03) s += bell(t - 0.03, 1568, 7, [[1, 1], [2.76, 0.5], [5.4, 0.25]]);
  if (t > 0.12) s += bell(t - 0.12, 2093, 6, [[1, 1], [2.76, 0.5], [5.4, 0.25]]);
  return s;
}, 0.7);
sfx('coin', 0.18, t => {
  const f = t < 0.06 ? note(83) : note(88);
  return Math.sign(Math.sin(TAU * f * t)) * 0.35 * Math.exp(-t * 14) + Math.sin(TAU * f * t) * 0.4 * Math.exp(-t * 10);
}, 0.45);
sfx('waste', 0.35, t => Math.sin(TAU * (150 - 120 * t) * t) * Math.exp(-t * 9) + noise() * 0.35 * Math.exp(-t * 25), 0.7);
sfx('arrive', 0.7, t => bell(t, 1760, 5, [[1, 1], [2.4, 0.35], [4.1, 0.15]]) + bell(Math.max(0, t - 0.12), 1397, 5, [[1, 0.8], [2.4, 0.3]]) * (t > 0.12 ? 1 : 0), 0.45);
sfx('angry', 0.4, t => {
  const f = 120 + 10 * Math.sin(TAU * 14 * t);
  const saw = 2 * ((f * t) % 1) - 1;
  return saw * 0.6 * Math.exp(-t * 5) * (t < 0.36 ? 1 : 0);
}, 0.5);
sfx('booster', 0.5, t => {
  const sweep = Math.sin(TAU * (300 * t + 1400 * t * t));
  return sweep * 0.5 * Math.sin(Math.PI * t / 0.5) + noise() * 0.3 * Math.sin(Math.PI * t / 0.5);
}, 0.6);
sfx('shuffle', 0.45, t => {
  let s = 0;
  for (let k = 0; k < 6; k++) { const tt = t - k * 0.06; if (tt > 0) s += noise() * Math.exp(-tt * 90) * 0.8 + Math.sin(TAU * 700 * tt) * Math.exp(-tt * 60) * 0.3; }
  return s;
}, 0.55);
sfx('star', 0.4, t => bell(t, note(96), 10) + bell(Math.max(0, t - 0.05), note(100), 10) * (t > 0.05 ? 0.7 : 0), 0.5);
sfx('win', 1.5, t => {
  const seq = [[0, 72], [0.12, 76], [0.24, 79], [0.36, 84]];
  let s = 0;
  for (const [st, n] of seq) { const tt = t - st; if (tt > 0) s += bell(tt, note(n), 4, [[1, 1], [2, 0.5], [3, 0.25]]); }
  if (t > 0.55) { const tt = t - 0.55; for (const n of [72, 76, 79, 84]) s += bell(tt, note(n), 2.2, [[1, 0.6], [2, 0.25]]); }
  return s;
}, 0.75);
sfx('lose', 1.0, t => {
  const seq = [[0, 67], [0.18, 65], [0.36, 62], [0.54, 59]];
  let s = 0;
  for (const [st, n] of seq) { const tt = t - st; if (tt > 0) s += bell(tt, note(n), 3.5, [[1, 1], [2, 0.3]]) * (1 - st); }
  return s;
}, 0.6);

// ------------------------------------------------------------------ music
// 8 bars, 104 BPM, C major: bass on 1 & 3, soft keys on 2 & 4, bell melody, brushed hat.
const MR = 16000;
const BPM = 104, BEAT = 60 / BPM, BARS = 8;
const LOOP = BARS * 4 * BEAT;
const n = Math.floor(LOOP * MR);
const music = new Float32Array(n);
function add(start, dur, fn, gain) {
  const s0 = Math.floor(start * MR), s1 = Math.floor((start + dur) * MR);
  for (let i = s0; i < s1; i++) {
    const t = (i - s0) / MR;
    music[i % n] += fn(t) * gain;   // tails wrap around: seamless loop
  }
}
const chords = [[48, [60, 64, 67]], [45, [57, 60, 64]], [41, [57, 60, 65]], [43, [55, 59, 62]],
  [48, [60, 64, 67]], [45, [57, 60, 64]], [50, [57, 62, 65]], [43, [55, 59, 62]]];
const melody = [
  [76, 1], [79, 0.5], [76, 0.5], [74, 1], [72, 1],
  [72, 1], [76, 0.5], [72, 0.5], [69, 2],
  [69, 1], [72, 0.5], [74, 0.5], [77, 1], [76, 1],
  [74, 1.5], [72, 0.5], [74, 2],
  [76, 1], [79, 0.5], [81, 0.5], [79, 1], [76, 1],
  [72, 1], [74, 0.5], [76, 0.5], [72, 2],
  [74, 1], [77, 0.5], [76, 0.5], [74, 1], [72, 1],
  [71, 1.5], [74, 0.5], [72, 2],
];
chords.forEach(([root, tri], bar) => {
  const t0 = bar * 4 * BEAT;
  for (const b of [0, 2]) add(t0 + b * BEAT, 1.2, t => Math.sin(TAU * note(root) * t) * Math.exp(-t * 3) + Math.sin(TAU * note(root) * 2 * t) * 0.2 * Math.exp(-t * 5), 0.5);
  for (const b of [1, 3]) for (const m of tri) add(t0 + b * BEAT, 0.9, t => (Math.sin(TAU * note(m) * t) + 0.3 * Math.sin(TAU * note(m) * 2 * t)) * Math.exp(-t * 4.5), 0.13);
  for (let k = 0; k < 8; k++) add(t0 + (k + 0.5) * BEAT / 2 - BEAT / 4, 0.06, t => noise() * Math.exp(-t * 80), k % 2 ? 0.05 : 0.025);
});
let mt = 0;
for (const [m, beats] of melody) {
  add(mt * BEAT, beats * BEAT + 0.6, t => bell(t, note(m), 3.2, [[1, 1], [2, 0.25], [3, 0.12]]), 0.22);
  mt += beats;
}
total += writeWav('music', normalize(music, 0.55), MR);
console.log(`sounds written, ${(total / 1024).toFixed(0)} KB (music loop ${LOOP.toFixed(2)} s, melody ${mt} beats)`);
