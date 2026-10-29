// HTML5 smoke test: serves a wasm-web bundle, runs it in headless Edge/Chrome with a mocked
// Poki SDK, collects the console and takes screenshots over the DevTools protocol.
//
// usage: node tools/web_smoke.js <bundle_dir_with_index.html> <out_dir> [options]
//   --size=360x720     viewport (CSS px)        --secs=20       run time
//   --shots=3,8,15     screenshot times (s)      --autoplay=1    bot plays (cafe.autoplay)
//   --level=N          start level               --fresh=1       ignore the save (default 1)
//   --clicks=t:x:y,... taps in viewport px       --dpr=1         device pixel ratio
//   --coins=N          start with N coins (cafe.debug_coins)
//   --popup=win|jam|pause|decor|settings   open a popup at start (cafe.debug_popup)
// Bundle first (from the project root):
//   java -cp <defold.jar> com.dynamo.bob.Bob --root . --platform wasm-web --architectures wasm-web
//        --variant debug --archive --bundle-output bundle/web build bundle
const fs = require('fs');
const path = require('path');
const http = require('http');
const { spawn, spawnSync } = require('child_process');

const [, , BUNDLE, OUT, ...rest] = process.argv;
const opt = { size: '360x720', secs: '20', shots: '3,8,15', autoplay: '1', level: '0', fresh: '1', clicks: '', dpr: '1', coins: '0', popup: '' };
for (const a of rest) {
  const m = a.match(/^--(\w+)=(.*)$/);
  if (m) opt[m[1]] = m[2];
}
const [VW, VH] = opt.size.split('x').map(Number);
const CLICKS = opt.clicks.split(',').filter(Boolean).map(c => c.split(':').map(Number));
const PORT = 8700 + Math.floor(Math.random() * 200);
const DEBUG_PORT = 9300 + Math.floor(Math.random() * 200);
const BROWSER = [
  'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',
  'C:/Program Files (x86)/Microsoft/EdgeCore/156.0.4314.50/msedge.exe',
  'C:/Program Files (x86)/Microsoft/EdgeCore/155.0.4283.45/msedge.exe',
  'C:/Program Files/Google/Chrome/Application/chrome.exe',
].find(p => fs.existsSync(p));

fs.mkdirSync(OUT, { recursive: true });

const POKI_MOCK = `<script>
window.PokiSDK = {
  init: () => Promise.resolve(),
  gameLoadingProgress() {}, gameLoadingFinished() { console.log('[poki] gameLoadingFinished'); },
  gameplayStart() { console.log('[poki] gameplayStart'); },
  gameplayStop() { console.log('[poki] gameplayStop'); },
  commercialBreak(cb) { console.log('[poki] commercialBreak'); if (cb) cb(); return Promise.resolve(); },
  rewardedBreak(o) { console.log('[poki] rewardedBreak'); if (o && o.onStart) o.onStart(); return Promise.resolve(true); },
  measure(a, b, c) { console.log('[poki] measure', a, b, c); },
  setDebug() {}, captureError(e) { console.log('[poki] error', e); },
  getURLParam() { return null; }, shareableURL() { return Promise.resolve(''); },
  getDeviceInfo() { return { category: 'mobile' }; }, movePill() {}, openExternalLink(u) { console.log('[poki] link', u); },
};
window.addEventListener('load', () => setTimeout(() => { if (window.poki_sdk_loaded) poki_sdk_loaded(); }, 50));
</script>`;

function patchedIndex() {
  let html = fs.readFileSync(path.join(BUNDLE, 'index.html'), 'utf8');
  html = html.replace(/<script[^>]*poki-sdk[^>]*><\/script>/, POKI_MOCK);
  const args = [];
  if (opt.fresh === '1') args.push('--config=cafe.fresh=1');
  if (opt.autoplay === '1') args.push('--config=cafe.autoplay=1');
  if (opt.level !== '0') args.push('--config=cafe.start_level=' + opt.level);
  if (opt.coins !== '0') args.push('--config=cafe.debug_coins=' + opt.coins);
  if (opt.popup) args.push('--config=cafe.debug_popup=' + opt.popup);
  html = html.replace(/var CUSTOMIZED_PARAMETERS[^;]*;|\/\/ override ProgressView[^\n]*/,
    m => m + `\nCUSTOM_PARAMETERS['engine_arguments'] = ${JSON.stringify(args)};`);
  return html;
}

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json' };
const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0]);
  if (url === '/' || url === '/index.html') {
    res.writeHead(200, { 'Content-Type': 'text/html' });
    return res.end(patchedIndex());
  }
  const file = path.join(path.resolve(BUNDLE), url);
  if (!file.startsWith(path.resolve(BUNDLE)) || !fs.existsSync(file) || fs.statSync(file).isDirectory()) {
    res.writeHead(404); return res.end();
  }
  res.writeHead(200, { 'Content-Type': MIME[path.extname(file)] || 'application/octet-stream' });
  fs.createReadStream(file).pipe(res);
});

const sleep = ms => new Promise(r => setTimeout(r, ms));

async function main() {
  await new Promise(r => server.listen(PORT, r));
  const profile = path.join(require('os').tmpdir(), 'cafe_smoke_profile_' + Date.now());
  const browser = spawn(BROWSER, [
    '--headless=new', `--remote-debugging-port=${DEBUG_PORT}`, `--user-data-dir=${profile}`,
    `--window-size=${VW + 40},${VH + 80}`, '--use-angle=swiftshader', '--enable-unsafe-swiftshader',
    '--autoplay-policy=no-user-gesture-required', '--no-first-run', 'about:blank',
  ], { stdio: 'ignore' });

  let targets;
  for (let i = 0; i < 150; i++) {
    try { targets = await (await fetch(`http://127.0.0.1:${DEBUG_PORT}/json`)).json(); break; } catch { await sleep(200); }
  }
  const page = targets && targets.find(t => t.type === 'page');
  if (!page) {
    console.error('browser did not start');
    spawn('taskkill', ['/PID', String(browser.pid), '/T', '/F'], { stdio: 'ignore' });
    process.exit(1);
  }
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  await new Promise(r => ws.addEventListener('open', r));
  let id = 0;
  const pending = new Map();
  const logs = [];
  ws.addEventListener('message', ev => {
    const m = JSON.parse(ev.data);
    if (m.id && pending.has(m.id)) { pending.get(m.id)(m.result); pending.delete(m.id); }
    if (m.method === 'Runtime.consoleAPICalled') {
      logs.push(m.params.args.map(a => a.value !== undefined ? a.value : a.description).join(' '));
    } else if (m.method === 'Runtime.exceptionThrown') {
      logs.push('EXCEPTION ' + JSON.stringify(m.params.exceptionDetails).slice(0, 400));
    }
  });
  const send = (method, params = {}) => new Promise(r => { const i = ++id; pending.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });

  await send('Runtime.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: VW, height: VH, deviceScaleFactor: Number(opt.dpr), mobile: false });
  await send('Page.navigate', { url: `http://127.0.0.1:${PORT}/` });

  const t0 = Date.now();
  for (const [t, x, y] of CLICKS) {
    setTimeout(async () => {
      // GLFW tracks the cursor from move events: move first
      await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y });
      await sleep(50);
      await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 });
      await sleep(60);
      await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 });
    }, t * 1000);
  }
  for (const s of opt.shots.split(',').filter(Boolean).map(Number)) {
    while (Date.now() - t0 < s * 1000) await sleep(100);
    const r = await send('Page.captureScreenshot', { format: 'png' });
    fs.writeFileSync(path.join(OUT, `web_${s}s.png`), Buffer.from(r.data, 'base64'));
  }
  while (Date.now() - t0 < Number(opt.secs) * 1000) await sleep(200);
  fs.writeFileSync(path.join(OUT, 'web_console.txt'), logs.join('\n'));
  ws.close();
  spawn('taskkill', ['/PID', String(browser.pid), '/T', '/F'], { stdio: 'ignore' });
  // headless Edge re-parents its helpers: also kill everything started with this profile
  const ps = "Get-CimInstance Win32_Process -Filter \"Name='msedge.exe' OR Name='chrome.exe'\" | " +
    `Where-Object { $_.CommandLine -like '*${path.basename(profile)}*' } | ` +
    'ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }';
  spawnSync('powershell.exe', ['-NoProfile', '-Command', ps], { stdio: 'ignore' });
  await sleep(500);
  server.close();
  console.log(`console lines: ${logs.length}`);
  const errors = logs.filter(l => /ERROR|EXCEPTION|attempt to|stack traceback/i.test(l));
  console.log(errors.slice(0, 30).join('\n') || 'no errors');
  process.exit(0);
}
main().catch(e => { console.error(e); process.exit(1); });
