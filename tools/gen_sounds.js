// Procedural sound effects and the looping cafe tune, encoded to Ogg Vorbis
// (a tiny sound stays WAV when that is smaller than the Vorbis headers).
// usage (from the project root):
//   npm install --prefix tools      (once: the Vorbis encoder, wasm-media-encoders)
//   node tools/gen_sounds.js
// Writes main/assets/sounds/*.ogg|wav and main/sounds.go (the sound components).
const fs = require('fs');
const path = require('path');
const { createOggEncoder } = require('wasm-media-encoders');

const OUT = 'main/assets/sounds';
const GO = 'main/sounds.go';
fs.mkdirSync(OUT, { recursive: true });

// deterministic noise / randomness
let seed = 12345;
const rnd = () => { seed = (seed * 16807) % 2147483647; return (seed - 1) / 2147483646; };
const noise = () => rnd() * 2 - 1;
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
function lowpass(buf, cutoff, rate) {
  const a = Math.exp(-TAU * cutoff / rate);
  let y = 0;
  for (let i = 0; i < buf.length; i++) { y = (1 - a) * buf[i] + a * y; buf[i] = y; }
  return buf;
}
function highpass(buf, cutoff, rate) {
  const a = Math.exp(-TAU * cutoff / rate);
  let y = 0;
  for (let i = 0; i < buf.length; i++) { y = (1 - a) * buf[i] + a * y; buf[i] -= y; }
  return buf;
}
const rms = buf => Math.sqrt(buf.reduce((s, v) => s + v * v, 0) / buf.length);
const env = (t, attack, decay, len = Infinity, release = 12) =>
  Math.min(1, t / attack) * Math.exp(-t * decay) * (t > len ? Math.exp(-(t - len) * release) : 1);

// ------------------------------------------------------------------ voices (t in seconds -> sample)
// bell / celesta: partials [ratio, gain, extra decay]
const bell = (f, decay, partials = [[1, 1, 0], [2, 0.35, 2], [3, 0.12, 5]]) => t =>
  partials.reduce((s, [m, a, d]) => s + a * Math.sin(TAU * f * m * t) * Math.exp(-t * d), 0) * env(t, 0.002, decay);
// warm Rhodes-like electric piano: 2-op FM, a detuned twin and a short tine
const epiano = (f, vel, len) => t => {
  const idx = (0.8 * vel + 0.35) * Math.exp(-t * 3.5) + 0.12;
  const w1 = TAU * f * t, w2 = TAU * f * 1.0025 * t;
  const body = 0.6 * Math.sin(w1 + idx * Math.sin(w1)) + 0.4 * Math.sin(w2 + idx * Math.sin(w2));
  const tine = 0.16 * vel * Math.sin(4 * w1) * Math.exp(-t * 14);
  return (body + tine) * env(t, 0.004, 1.25, len, 9) * vel;
};
// round finger bass
const bass = (f, vel, len) => t => {
  const w = TAU * f * t;
  return (Math.sin(w) + 0.24 * Math.sin(2 * w) + 0.07 * Math.sin(3 * w)) * env(t, 0.012, 1.7, len, 14) * vel;
};
// music-box lead with a gentle vibrato that fades in
const lead = (f, vel, len) => t => {
  const depth = Math.min(1, Math.max(0, t - 0.2) * 3) * f * 0.004 / 5.2;
  const w = TAU * f * t + depth * Math.sin(TAU * 5.2 * t);
  const s = Math.sin(w) + 0.3 * Math.sin(2 * w) * Math.exp(-t * 3) + 0.1 * Math.sin(3 * w) * Math.exp(-t * 6)
    + 0.16 * Math.sin(4 * w) * Math.exp(-t * 12);
  return s * env(t, 0.006, 1.9, len, 6) * vel;
};
// soft string-ish pad: three detuned sines per note
const pad = (f, len) => t => {
  const a = Math.min(1, t / 0.45) * (t > len ? Math.exp(-(t - len) * 4) : 1);
  return (Math.sin(TAU * f * t) + Math.sin(TAU * f * 1.004 * t) + Math.sin(TAU * f * 0.996 * t)) * a / 3;
};

// ------------------------------------------------------------------ sound effects
const SR = 22050;
const sounds = [];   // { name, buf, rate, q, loop }
function sfx(name, dur, fn, peak = 0.8, post) {
  let buf = render(dur, SR, fn);
  if (post) buf = post(buf);
  sounds.push({ name, buf: fade(normalize(buf, peak), SR), rate: SR, q: 4 });
}
// a short noise burst, band-limited
function noiseBuf(dur, lo, hi, decay) {
  const b = render(dur, SR, t => noise() * Math.exp(-t * decay));
  if (hi) lowpass(b, hi, SR);
  if (lo) highpass(b, lo, SR);
  return b;
}
const at = (t, start, fn) => t >= start ? fn(t - start) : 0;
// a few random high bell grains (shimmer)
function shimmer(count, from, to, span, gain) {
  const g = [];
  for (let k = 0; k < count; k++) g.push([from + rnd() * (to - from), rnd() * span]);
  return t => g.reduce((s, [f, st]) => s + at(t, st, tt => Math.sin(TAU * f * tt) * Math.exp(-tt * 28)), 0) * gain;
}

// pick: a light rising "boop" (pitch varies at runtime)
sfx('tap', 0.11, t => Math.sin(TAU * (1200 * t - 500 * (1 - Math.exp(-40 * t)) / 40)) * env(t, 0.002, 34)
  + noise() * 0.05 * Math.exp(-t * 500), 0.5);
// undo: a soft falling "tok"
sfx('place', 0.09, t => Math.sin(TAU * (350 * t + 150 * (1 - Math.exp(-50 * t)) / 50)) * env(t, 0.002, 45)
  + 0.3 * Math.sin(TAU * 1050 * t) * Math.exp(-t * 90), 0.5);
sfx('button', 0.08, t => (Math.sin(TAU * (1000 * t + 300 * t * t)) + 0.2 * Math.sin(TAU * 2000 * t)) * env(t, 0.002, 55), 0.42);
// covered tile: a muffled "bonk"
sfx('blocked', 0.16, t => {
  const ph = TAU * (175 * t + 90 * (1 - Math.exp(-30 * t)) / 30);
  return (Math.sin(ph) + 0.2 * Math.sin(3 * ph)) * env(t, 0.003, 22);
}, 0.42, b => lowpass(b, 1400, SR));
// three of a kind: sparkly chime (pitched up at runtime with the combo)
{
  const notes = [[84, 0], [88, 0.05], [91, 0.1]].map(([n, s]) => [bell(note(n), 6, [[1, 1, 0], [2, 0.35, 2], [3, 0.12, 5], [4.2, 0.08, 8]]), s]);
  const sh = shimmer(7, 3000, 6000, 0.25, 0.08);
  sfx('match', 0.62, t => notes.reduce((s, [fn, st]) => s + at(t, st, fn), 0) + sh(t), 0.62);
}
// order served: a counter bell
{
  const p = [[1, 1, 0], [2.76, 0.35, 3], [5.4, 0.12, 8]];
  const b1 = bell(1568, 4, p), b2 = bell(2093, 4, p);
  sfx('serve', 0.75, t => b1(t) + at(t, 0.1, b2) * 0.9 + noise() * 0.06 * Math.exp(-t * 200), 0.58);
}
sfx('coin', 0.28, t => {
  const f = t < 0.055 ? 1976 : 2637, tt = t < 0.055 ? t : t - 0.055;
  return (Math.sin(TAU * f * tt) + 0.15 * Math.sin(TAU * 3 * f * tt)) * Math.exp(-tt * 18) * Math.min(1, tt / 0.002);
}, 0.4);
// to the bin: a soft "whump"
{
  const nb = noiseBuf(0.35, 0, 1200, 9);
  sfx('waste', 0.35, (t, i) => Math.sin(TAU * (80 * t + 140 * (1 - Math.exp(-8 * t)) / 8)) * env(t, 0.004, 9)
    + nb[i] * 0.8 * Math.sin(Math.PI * Math.min(1, t / 0.3)), 0.45);
}
// a guest arrives: the door chime
{
  const p = [[1, 1, 0], [2.4, 0.3, 3], [4.1, 0.1, 6]];
  const b1 = bell(1760, 5, p), b2 = bell(1397, 5, p);
  sfx('arrive', 0.8, t => b1(t) + at(t, 0.13, b2), 0.38);
}
// an impatient guest leaves: a soft "hmph"
sfx('angry', 0.38, t => {
  const ph = TAU * (220 * t + 110 * (1 - Math.exp(-6 * t)) / 6) + 0.5 * Math.sin(TAU * 7 * t);
  return (Math.sin(ph) + 0.25 * Math.sin(2 * ph) + 0.1 * Math.sin(3 * ph)) * env(t, 0.02, 5);
}, 0.38, b => lowpass(b, 1800, SR));
// booster: a magic sweep with sparkles
{
  const sh = shimmer(10, 1500, 4500, 0.4, 0.12);
  sfx('booster', 0.55, t => Math.sin(TAU * (500 * t + 1300 * t * t * 1.6)) * Math.sin(Math.PI * Math.min(1, t / 0.5)) * 0.6 + sh(t), 0.52);
}
// shuffle: a soft card riffle
{
  const ticks = [];
  for (let k = 0; k < 8; k++) ticks.push([k * 0.035, noiseBuf(0.05, 2000, 7000, 110)]);
  sfx('shuffle', 0.4, t => ticks.reduce((s, [st, nb]) => {
    const i = Math.floor((t - st) * SR);
    return s + (i >= 0 && i < nb.length ? nb[i] + 0.25 * Math.sin(TAU * 900 * (t - st)) * Math.exp(-(t - st) * 80) : 0);
  }, 0), 0.45);
}
{
  const b1 = bell(2093, 8), b2 = bell(3136, 8);
  sfx('star', 0.45, t => b1(t) + at(t, 0.06, b2) * 0.8, 0.45);
}
// level complete: a happy jingle
{
  const arp = [72, 76, 79, 84, 88].map((n, k) => [lead(note(n), 0.9, 0.12), k * 0.09]);
  const chord = [72, 76, 79, 84].map(n => epiano(note(n), 0.7, 0.9));
  const sh = shimmer(14, 2500, 6000, 1.2, 0.05);
  sfx('win', 1.8, t => arp.reduce((s, [fn, st]) => s + at(t, st, fn), 0)
    + at(t, 0.5, tt => chord.reduce((s, fn) => s + fn(tt), 0) * 0.45) + sh(t), 0.68);
}
// kitchen jam: a gentle "aww"
{
  const notes = [[67, 0], [64, 0.22]].map(([n, s]) => [epiano(note(n), 0.7, 0.25), s]);
  sfx('lose', 1.2, t => notes.reduce((s, [fn, st]) => s + at(t, st, fn), 0)
    + at(t, 0.44, tt => {
      const f = note(60) * Math.pow(2, -Math.min(1, tt / 0.5) / 12);
      return Math.sin(TAU * f * tt + 0.6 * Math.sin(TAU * f * tt) * Math.exp(-tt * 3)) * env(tt, 0.004, 1.6, 0.6, 5) * 0.8;
    }), 0.5);
}
// a cloche lifts: ta-da
{
  const notes = [91, 95, 98, 103].map((n, k) => [bell(note(n), 7), k * 0.035]);
  const sh = shimmer(6, 3500, 7000, 0.3, 0.07);
  sfx('reveal', 0.55, t => notes.reduce((s, [fn, st]) => s + at(t, st, fn), 0) + sh(t), 0.42);
}
// golden tile: a shimmering coin
{
  const sh = shimmer(10, 2500, 5200, 0.3, 0.2);
  const b = bell(2637, 7);
  sfx('sparkle', 0.55, t => b(t) * 0.7 + sh(t), 0.45);
}
// gift box opens
{
  const nb = noiseBuf(0.3, 200, 2500, 14);
  const arp = [79, 84, 88, 91].map((n, k) => [lead(note(n), 0.9, 0.1), 0.08 + k * 0.07]);
  const sh = shimmer(12, 2500, 6500, 0.8, 0.06);
  sfx('gift', 1.0, (t, i) => (i < nb.length ? nb[i] * 0.5 : 0) + arp.reduce((s, [fn, st]) => s + at(t, st, fn), 0) + sh(t), 0.6);
}

// ------------------------------------------------------------------ music
// "Sweet cafe": 16 bars of bossa-lounge in F major, 92 BPM (A section + B section).
// Electric piano comping, finger bass, music-box melody, brushes, a pad in B and a reverb send.
const MR = 24000;
const BPM = 92, BEAT = 60 / BPM, BARS = 16;
const LOOP = BARS * 4 * BEAT;
const N = Math.round(LOOP * MR);
const dry = new Float32Array(N), send = new Float32Array(N);
// tails wrap around the loop end: the loop is seamless
function play(start, dur, fn, gain, rev = 0) {
  const s0 = Math.round(start * MR), len = Math.round(dur * MR);
  for (let i = 0; i < len; i++) {
    const v = fn(i / MR) * gain, k = ((s0 + i) % N + N) % N;
    dry[k] += v;
    if (rev) send[k] += v * rev;
  }
}
function playBuf(start, buf, gain, rev = 0) {
  const s0 = Math.round(start * MR);
  for (let i = 0; i < buf.length; i++) {
    const v = buf[i] * gain, k = ((s0 + i) % N + N) % N;
    dry[k] += v;
    if (rev) send[k] += v * rev;
  }
}
const human = (k = 0.006) => (rnd() * 2 - 1) * k;

// [bass root, voicing, beats]
const F9 = [41, [57, 60, 64, 67]], Dm9 = [38, [57, 60, 64, 65]], Gm9 = [43, [58, 62, 65, 69]], C9 = [36, [58, 62, 64, 67]];
const Am7 = [45, [55, 60, 64, 67]], Bbmaj7 = [34, [57, 62, 65, 69]], Bbmaj9 = [34, [57, 60, 62, 65]];
const C7sus = [36, [58, 60, 65, 67]], D7 = [38, [54, 57, 60, 64]];
const seg = (c, beats) => [c[0], c[1], beats];
const bars = [
  [seg(F9, 4)], [seg(Dm9, 4)], [seg(Gm9, 4)], [seg(C9, 4)],
  [seg(F9, 4)], [seg(Am7, 4)], [seg(Bbmaj7, 4)], [seg(C7sus, 2), seg(C9, 2)],
  [seg(Bbmaj9, 4)], [seg(Am7, 4)], [seg(Gm9, 4)], [seg(F9, 4)],
  [seg(Bbmaj9, 4)], [seg(Am7, 2), seg(D7, 2)], [seg(Gm9, 4)], [seg(C9, 4)],
];
const melody = [
  [[null, 0.5], [81, 0.5], [79, 0.5], [81, 0.5], [84, 1.5], [81, 0.5]],
  [[79, 1], [77, 0.5], [76, 0.5], [77, 2]],
  [[null, 0.5], [82, 0.5], [81, 0.5], [79, 0.5], [77, 1], [74, 1]],
  [[76, 1.5], [77, 0.5], [79, 2]],
  [[null, 0.5], [81, 0.5], [79, 0.5], [81, 0.5], [84, 1], [86, 0.5], [84, 0.5]],
  [[81, 1.5], [79, 0.5], [76, 2]],
  [[77, 1], [79, 0.5], [81, 0.5], [74, 1], [77, 1]],
  [[79, 1.5], [77, 0.5], [76, 1], [null, 1]],
  [[74, 1], [77, 1], [81, 1.5], [79, 0.5]],
  [[76, 1], [79, 1], [84, 1.5], [81, 0.5]],
  [[82, 1], [81, 0.5], [79, 0.5], [77, 1], [74, 1]],
  [[76, 1.5], [77, 0.5], [81, 2]],
  [[86, 1], [84, 0.5], [82, 0.5], [81, 1], [77, 1]],
  [[84, 1], [81, 1], [78, 1], [81, 1]],
  [[79, 1], [82, 1], [81, 0.5], [79, 0.5], [77, 1]],
  [[76, 1], [79, 0.5], [77, 0.5], [76, 1], [72, 1]],
];

// drums, pre-rendered
const kick = render(0.35, MR, t => Math.sin(TAU * (48 * t + 70 * (1 - Math.exp(-t * 25)) / 25)) * env(t, 0.002, 10));
const rimNoise = render(0.12, MR, t => noise() * Math.exp(-t * 55));
highpass(lowpass(rimNoise, 4000, MR), 1200, MR);
const rim = rimNoise.map((v, i) => v + 0.3 * Math.sin(TAU * 1800 * i / MR) * Math.exp(-i / MR * 90));
const shaker = render(0.09, MR, t => noise() * env(t, 0.01, 45));
highpass(shaker, 5000, MR);

bars.forEach((segs, b) => {
  const t0 = b * 4 * BEAT;
  let beat = 0;
  for (const [root, voicing, beats] of segs) {
    const ts = t0 + beat * BEAT;
    // bossa bass: root (dotted quarter), fifth on the "and", per two beats
    const fifth = root + 7 > 45 ? root - 5 : root + 7;
    for (let h = 0; h < beats; h += 2) {
      play(ts + h * BEAT + human(), 1.6 * BEAT, bass(note(root), 0.95, 1.4 * BEAT), 0.5);
      play(ts + (h + 1.5) * BEAT + human(), 0.9 * BEAT, bass(note(fifth), 0.75, 0.45 * BEAT), 0.5);
    }
    // e-piano comping
    const hits = beats === 4 ? (b % 2 ? [[0, 1, 0.85], [1.5, 0.75, 0.62], [2.5, 1, 0.7], [3.5, 0.4, 0.5]] : [[0, 1, 0.85], [1.5, 0.75, 0.62], [3, 0.8, 0.7]])
      : [[0, 1, 0.8], [1.5, 0.4, 0.55]];
    for (const [off, len, vel] of hits) {
      voicing.forEach((m, k) => play(ts + off * BEAT + k * 0.004 + human(0.004), len * BEAT + 0.8,
        epiano(note(m), vel * (0.92 + rnd() * 0.16), len * BEAT), 0.13, 0.35));
    }
    // pad in the B section
    if (b >= 8) for (const m of voicing) play(ts, beats * BEAT + 0.6, pad(note(m + 12), beats * BEAT), 0.035, 0.6);
    beat += beats;
  }
  // brushes
  playBuf(t0 + human(0.003), kick, 0.36);
  playBuf(t0 + 2 * BEAT + human(0.003), kick, 0.28);
  if (b % 2) playBuf(t0 + 3.5 * BEAT, kick, 0.16);
  playBuf(t0 + 1 * BEAT + human(0.004), rim, 0.13, 0.4);
  playBuf(t0 + 3 * BEAT + human(0.004), rim, 0.13, 0.4);
  if (b % 2 === 0) playBuf(t0 + 2.5 * BEAT + human(0.004), rim, 0.07, 0.4);
  if (b === BARS - 1) for (const k of [3.33, 3.66]) playBuf(t0 + k * BEAT, rim, 0.06, 0.4);
  for (let k = 0; k < 8; k++) playBuf(t0 + k * BEAT / 2 + human(0.004), shaker, (k % 2 ? 0.055 : 0.03) * (0.8 + rnd() * 0.4));
  // melody
  let mt = t0;
  for (const [m, beats] of melody[b]) {
    if (m) play(mt + human(0.004), beats * BEAT + 1.2, lead(note(m), 0.8 + rnd() * 0.15, beats * BEAT * 0.9), 0.3, 0.45);
    mt += beats * BEAT;
  }
  // a glittering harp run into each section
  if (b === 0 || b === 8) {
    const tones = segs[0][1].map(m => m + 24).concat(segs[0][1].map(m => m + 36)).slice(0, 7);
    tones.forEach((m, k) => play(t0 + k * 0.055, 0.8, lead(note(m), 0.35, 0.08), 0.12, 0.8));
  }
});

// Freeverb-style mono reverb over the send; run twice so the tail wraps into the loop start
function reverb(input) {
  const scale = MR / 44100;
  const combs = [1116, 1188, 1277, 1356, 1422, 1491].map(d => ({ buf: new Float32Array(Math.round(d * scale)), i: 0, store: 0 }));
  const aps = [556, 441, 341].map(d => ({ buf: new Float32Array(Math.round(d * scale)), i: 0 }));
  const out = new Float32Array(N), fb = 0.82, damp = 0.35;
  for (let pass = 0; pass < 2; pass++) {
    for (let n = 0; n < N; n++) {
      const x = input[n] * 0.05;
      let acc = 0;
      for (const c of combs) {
        const y = c.buf[c.i];
        c.store = y * (1 - damp) + c.store * damp;
        c.buf[c.i] = x + c.store * fb;
        c.i = (c.i + 1) % c.buf.length;
        acc += y;
      }
      for (const a of aps) {
        const b = a.buf[a.i];
        a.buf[a.i] = acc + b * 0.5;
        a.i = (a.i + 1) % a.buf.length;
        acc = b - acc;
      }
      if (pass === 1) out[n] = acc;
    }
  }
  return out;
}
const wet = reverb(send);
const wetGain = 0.55 * rms(send) / (rms(wet) || 1);
const music = new Float32Array(N);
for (let i = 0; i < N; i++) music[i] = dry[i] + wet[i] * wetGain;
// warm master: rumble cut, gentle low-pass and soft saturation. The filters are warmed up on
// the loop end, so the first sample continues the last one.
function loopFilter(buf, fn) {
  const pre = Math.min(buf.length, MR);
  const tmp = new Float32Array(pre + buf.length);
  tmp.set(buf.subarray(buf.length - pre), 0);
  tmp.set(buf, pre);
  fn(tmp);
  buf.set(tmp.subarray(pre));
}
loopFilter(music, b => lowpass(highpass(b, 30, MR), 8500, MR));
const pk = music.reduce((m, v) => Math.max(m, Math.abs(v)), 0);
for (let i = 0; i < N; i++) music[i] = Math.tanh(music[i] / pk * 1.3) / Math.tanh(1.3);
sounds.push({ name: 'music', buf: normalize(music, 0.82), rate: MR, q: 2, loop: true });

// ------------------------------------------------------------------ encode + sounds.go
function wav(buf, rate) {
  const data = Buffer.alloc(buf.length * 2);
  for (let i = 0; i < buf.length; i++) data.writeInt16LE(Math.round(Math.max(-1, Math.min(1, buf[i])) * 32767), i * 2);
  const h = Buffer.alloc(44);
  h.write('RIFF', 0); h.writeUInt32LE(36 + data.length, 4); h.write('WAVE', 8);
  h.write('fmt ', 12); h.writeUInt32LE(16, 16); h.writeUInt16LE(1, 20); h.writeUInt16LE(1, 22);
  h.writeUInt32LE(rate, 24); h.writeUInt32LE(rate * 2, 28); h.writeUInt16LE(2, 32); h.writeUInt16LE(16, 34);
  h.write('data', 36); h.writeUInt32LE(data.length, 40);
  return Buffer.concat([h, data]);
}
async function ogg(buf, rate, q) {
  const enc = await createOggEncoder();
  enc.configure({ channels: 1, sampleRate: rate, vbrQuality: q });
  // encode() returns a view into the encoder memory: copy before the next call
  const head = Buffer.from(enc.encode([buf]));
  return Buffer.concat([head, Buffer.from(enc.finalize())]);
}

(async () => {
  let total = 0;
  const comps = [];
  for (const s of sounds) {
    const w = wav(s.buf, s.rate), o = await ogg(s.buf, s.rate, s.q);
    const useOgg = o.length < w.length * 0.85;
    const ext = useOgg ? 'ogg' : 'wav', data = useOgg ? o : w;
    for (const e of ['ogg', 'wav']) {
      const p = path.join(OUT, `${s.name}.${e}`);
      if (e !== ext && fs.existsSync(p)) fs.unlinkSync(p);
    }
    fs.writeFileSync(path.join(OUT, `${s.name}.${ext}`), data);
    total += data.length;
    console.log(`${s.name.padEnd(8)} ${ext} ${(data.length / 1024).toFixed(1).padStart(6)} KB  (${(s.buf.length / s.rate).toFixed(2)} s, wav ${(w.length / 1024).toFixed(0)} KB)`);
    comps.push([
      'embedded_components {',
      `  id: "${s.name}"`,
      '  type: "sound"',
      `  data: "sound: \\"/${OUT}/${s.name}.${ext}\\"\\n"`,
      `  "looping: ${s.loop ? 1 : 0}\\n"`,
      `  "group: \\"${s.loop ? 'music' : 'sfx'}\\"\\n"`,
      '  "gain: 1.0\\n"',
      '}',
    ].join('\n'));
  }
  fs.writeFileSync(GO, comps.join('\n') + '\n');
  console.log(`sounds: ${sounds.length}, ${(total / 1024).toFixed(0)} KB (music loop ${LOOP.toFixed(2)} s)`);
})();
