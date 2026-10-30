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
// to the display case: a glassy two-note "ting-ting" with a little shimmer
{
  const p = [[1, 1, 0], [2.92, 0.22, 4], [5.1, 0.06, 9]];
  const b1 = bell(note(88), 7, p), b2 = bell(note(93), 6, p);
  const sh = shimmer(5, 4000, 7000, 0.2, 0.05);
  sfx('showcase', 0.6, t => b1(t) * 0.8 + at(t, 0.07, b2) + sh(t), 0.42);
}
// a guest arrives: the door chime
{
  const p = [[1, 1, 0], [2.4, 0.3, 3], [4.1, 0.1, 6]];
  const b1 = bell(1760, 5, p), b2 = bell(1397, 5, p);
  sfx('arrive', 0.8, t => b1(t) + at(t, 0.13, b2), 0.38);
}
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
// Procedural fallback or loaded background music track
function genProceduralMusic() {
  const MR = 24000;
  const BPM = 92, BEAT = 60 / BPM, BARS = 16;
  const LOOP = BARS * 4 * BEAT;
  const N = Math.round(LOOP * MR);
  const dry = new Float32Array(N), send = new Float32Array(N);
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
  const chordF = [53, 57, 60, 64], chordGm = [55, 58, 62, 65];
  const chordAm = [57, 60, 64, 67], chordBb = [58, 62, 65, 69];
  const chordC7 = [48, 55, 58, 60, 65], chordD7 = [50, 54, 57, 60];
  const BARS_CHORDS = [
    chordF, chordGm, chordAm, chordBb,
    chordF, chordGm, chordC7, chordF,
    chordBb, chordAm, chordGm, chordF,
    chordGm, chordD7, chordGm, chordC7,
  ];
  const COMP_PATTERN = [0, 0.75, 1.5, 2.5, 3.25];
  for (let b = 0; b < BARS; b++) {
    const ch = BARS_CHORDS[b];
    for (const beat of COMP_PATTERN) {
      const st = (b * 4 + beat) * BEAT;
      const v = 0.55 + rnd() * 0.15;
      ch.forEach((n, k) => play(st + k * 0.003, 1.8 * BEAT, epiano(note(n), v, 1.4 * BEAT), 0.35, 0.45));
    }
  }
  const BASS_NOTES = [
    [41, 48, 41, 48], [43, 50, 43, 50], [45, 52, 45, 52], [46, 53, 46, 53],
    [41, 48, 41, 48], [43, 50, 43, 50], [36, 43, 36, 43], [41, 48, 41, 48],
    [46, 53, 46, 53], [45, 52, 45, 52], [43, 50, 43, 50], [41, 48, 41, 48],
    [43, 50, 43, 50], [38, 45, 38, 45], [43, 50, 43, 50], [36, 43, 36, 43],
  ];
  for (let b = 0; b < BARS; b++) {
    const pat = BASS_NOTES[b];
    for (let k = 0; k < 4; k++) {
      const st = (b * 4 + k + (k % 2 === 1 ? 0.5 : 0)) * BEAT;
      play(st, 0.85 * BEAT, bass(note(pat[k]), 0.85, 0.6 * BEAT), 0.52);
    }
  }
  const MELODY = [
    [0.0, 69, 0.6, 0.8], [0.75, 67, 0.5, 0.5], [1.5, 65, 0.7, 1.0], [3.0, 67, 0.6, 0.7],
    [4.5, 69, 0.8, 0.9], [5.5, 72, 0.7, 0.7], [6.5, 69, 0.6, 1.4],
    [8.0, 72, 0.7, 0.7], [9.0, 74, 0.8, 0.7], [10.0, 76, 0.9, 1.3], [11.5, 74, 0.6, 0.8],
    [12.5, 72, 0.7, 1.0], [14.0, 69, 0.6, 1.6],
    [16.0, 69, 0.6, 0.8], [16.75, 67, 0.5, 0.5], [17.5, 65, 0.7, 1.0], [19.0, 67, 0.6, 0.7],
    [20.5, 69, 0.8, 0.9], [21.5, 72, 0.7, 0.7], [22.5, 76, 0.8, 1.6],
    [24.5, 74, 0.7, 0.8], [25.5, 72, 0.6, 0.6], [26.0, 69, 0.7, 1.0], [27.5, 67, 0.6, 0.9],
    [28.5, 65, 0.8, 2.4],
    [32.0, 77, 0.8, 0.9], [33.0, 76, 0.7, 0.7], [34.0, 74, 0.8, 1.2], [35.5, 72, 0.6, 0.6],
    [36.5, 74, 0.7, 0.8], [37.5, 76, 0.8, 0.8], [38.5, 72, 0.7, 1.6],
    [40.0, 70, 0.7, 0.7], [41.0, 69, 0.6, 0.6], [42.0, 67, 0.7, 1.2], [43.5, 65, 0.6, 0.6],
    [44.5, 67, 0.8, 1.8],
    [48.0, 69, 0.7, 0.7], [49.0, 70, 0.7, 0.7], [50.0, 72, 0.8, 1.0], [51.5, 74, 0.7, 0.8],
    [52.5, 72, 0.8, 0.8], [53.5, 69, 0.7, 0.8], [54.5, 67, 0.7, 1.4],
    [56.5, 65, 0.7, 0.8], [57.5, 67, 0.7, 0.7], [58.5, 69, 0.8, 1.0], [60.0, 67, 0.8, 2.6],
  ];
  for (const [beat, n, vel, len] of MELODY) {
    play(beat * BEAT, len * BEAT + 0.5, lead(note(n), vel, len * BEAT), 0.42, 0.6);
  }
  const PAD_CHORDS = [
    [58, 62, 65], [57, 60, 64], [55, 58, 62], [53, 57, 60],
    [55, 58, 62], [54, 57, 60], [55, 58, 62], [55, 58, 60],
  ];
  for (let b = 0; b < 8; b++) {
    const ch = PAD_CHORDS[b];
    for (const n of ch) play((8 + b) * 4 * BEAT, 4.2 * BEAT, pad(note(n), 4 * BEAT), 0.16, 0.8);
  }
  const shk = shaker(0.06, 4500, 9000);
  for (let b = 0; b < BARS; b++) {
    for (let k = 0; k < 8; k++) {
      const t = (b * 4 + k * 0.5) * BEAT;
      const v = k % 2 === 0 ? 0.35 : 0.2;
      playBuf(t, shk, v * 0.6, 0.2);
    }
  }
  function reverb(inp) {
    const out = new Float32Array(inp.length);
    const delays = [1117, 1361, 1543, 1723, 1949, 2137].map(d => Math.round(d * MR / 24000));
    const feedbacks = [0.76, 0.74, 0.72, 0.70, 0.68, 0.66];
    for (let pass = 0; pass < 2; pass++) {
      for (let c = 0; c < delays.length; c++) {
        const d = delays[c], fb = feedbacks[c];
        const ring = new Float32Array(d);
        let ptr = 0;
        for (let i = 0; i < inp.length; i++) {
          const delayed = ring[ptr];
          const acc = inp[i] + delayed * fb;
          ring[ptr] = acc;
          ptr = (ptr + 1) % d;
          if (pass === 1) out[i] += delayed / delays.length;
        }
      }
    }
    return out;
  }
  const wet = reverb(send);
  const wetGain = 0.55 * rms(send) / (rms(wet) || 1);
  const music = new Float32Array(N);
  for (let i = 0; i < N; i++) music[i] = dry[i] + wet[i] * wetGain;
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
  return { name: 'music', buf: normalize(music, 0.82), rate: MR, q: 2, loop: true, dur: LOOP };
}

async function loadMusicFile(file) {
  const { MPEGDecoder } = require(path.join(__dirname, 'node_modules', 'mpg123-decoder'));
  const dec = new MPEGDecoder();
  await dec.ready;
  const raw = fs.readFileSync(file);
  const { channelData, sampleRate: srcRate } = dec.decode(raw);
  const targetRate = 32000;
  // Anti-aliasing filter before downsampling
  const chL = lowpass(channelData[0], targetRate * 0.46, srcRate);
  const chR = channelData[1] ? lowpass(channelData[1], targetRate * 0.46, srcRate) : chL;
  const ratio = srcRate / targetRate;
  const outLen = Math.floor(chL.length / ratio);
  const outL = new Float32Array(outLen);
  const outR = new Float32Array(outLen);
  for (let i = 0; i < outLen; i++) {
    const srcIdx = i * ratio;
    const i0 = Math.floor(srcIdx);
    const i1 = Math.min(i0 + 1, chL.length - 1);
    const frac = srcIdx - i0;
    outL[i] = chL[i0] * (1 - frac) + chL[i1] * frac;
    outR[i] = chR[i0] * (1 - frac) + chR[i1] * frac;
  }
  fade(outL, targetRate, 40);
  fade(outR, targetRate, 40);
  normalize(outL, 0.85);
  normalize(outR, 0.85);
  const dur = outL.length / targetRate;
  return { name: 'music', buf: [outL, outR], rate: targetRate, q: 0, loop: true, dur };
}

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
async function ogg(bufOrChannels, rate, q) {
  const enc = await createOggEncoder();
  const channels = Array.isArray(bufOrChannels) ? bufOrChannels : [bufOrChannels];
  enc.configure({ channels: channels.length, sampleRate: rate, vbrQuality: q });
  const chunk = 65536;
  const bufs = [];
  for (let i = 0; i < channels[0].length; i += chunk) {
    const slices = channels.map(c => c.subarray(i, Math.min(i + chunk, channels[0].length)));
    const res = enc.encode(slices);
    if (res && res.length) bufs.push(Buffer.from(res));
  }
  const fin = enc.finalize();
  if (fin && fin.length) bufs.push(Buffer.from(fin));
  return Buffer.concat(bufs);
}

(async () => {
  const musicFile = [
    path.join(__dirname, 'music.mp3'),
    path.join(__dirname, 'assets', 'music.mp3'),
  ].find(p => fs.existsSync(p));

  let musicItem;
  if (musicFile) {
    console.log('Loading background music from ' + musicFile + '...');
    musicItem = await loadMusicFile(musicFile);
  } else {
    musicItem = genProceduralMusic();
  }
  sounds.push(musicItem);

  let total = 0;
  const comps = [];
  for (const s of sounds) {
    const isStereo = Array.isArray(s.buf);
    const w = isStereo ? null : wav(s.buf, s.rate);
    const o = await ogg(s.buf, s.rate, s.q);
    const useOgg = isStereo || o.length < w.length * 0.85;
    const ext = useOgg ? 'ogg' : 'wav', data = useOgg ? o : w;
    for (const e of ['ogg', 'wav']) {
      const p = path.join(OUT, `${s.name}.${e}`);
      if (e !== ext && fs.existsSync(p)) fs.unlinkSync(p);
    }
    fs.writeFileSync(path.join(OUT, `${s.name}.${ext}`), data);
    total += data.length;
    const dur = s.dur || (isStereo ? (s.buf[0].length / s.rate) : (s.buf.length / s.rate));
    console.log(`${s.name.padEnd(8)} ${ext} ${(data.length / 1024).toFixed(1).padStart(6)} KB  (${dur.toFixed(2)} s${w ? `, wav ${(w.length / 1024).toFixed(0)} KB` : ''})`);
    comps.push([
      'embedded_components {',
      '  id: "' + s.name + '"',
      '  type: "sound"',
      '  data: "sound: \\"/' + OUT + '/' + s.name + '.' + ext + '\\"\\n"',
      '  "looping: ' + (s.loop ? 1 : 0) + '\\n"',
      '  "group: \\"' + (s.loop ? 'music' : 'sfx') + '\\"\\n"',
      '  "gain: 1.0\\n"',
      '}',
    ].join('\n'));
  }
  fs.writeFileSync(GO, comps.join('\n') + '\n');
  console.log(`sounds: ${sounds.length}, ${(total / 1024).toFixed(0)} KB (music loop ${musicItem.dur.toFixed(2)} s)`);
})();
