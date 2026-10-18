const assert = require('node:assert/strict'), fs = require('node:fs'), path = require('node:path'), ts = require('typescript');
const { chromium } = require('playwright');
// No dev server: a tiny static page (written under artifacts/camera/) plus the transpiled cameraSession module,
// both served through request interception. Every other request is aborted and fails the run.

const root = path.join(__dirname, '..'), outDir = path.join(root, 'artifacts', 'camera');
const origin = 'http://127.0.0.1:47631';
const sessionJs = ts.transpileModule(fs.readFileSync(path.join(root, 'src/lib/camera/cameraSession.ts'), 'utf8'),
  { compilerOptions: { module: ts.ModuleKind.ES2020, target: ts.ScriptTarget.ES2020 } }).outputText;
const html = `<!doctype html><meta charset="utf-8"><title>Camera local check</title><link rel="icon" href="data:,">
<button id="start">Start camera</button><button id="stop">Turn off</button>
<p id="state">off</p><video id="view" muted playsinline autoplay></video>
<script type="module">
import { createCameraSession } from '/cameraSession.js';
const video = document.getElementById('view'), label = document.getElementById('state');
const session = createCameraSession({ mediaDevices: navigator.mediaDevices, onChange: state => {
  label.textContent = state; video.srcObject = state === 'on' ? session.stream : null;
} });
let last = null;
document.getElementById('start').onclick = async () => { await session.start(); last = session.stream; };
document.getElementById('stop').onclick = () => session.stop();
window.__camera = {
  state: () => session.state,
  tracks: () => (last ? last.getTracks() : []).map(t => ({ kind: t.kind, readyState: t.readyState })),
};
</script>`;
fs.mkdirSync(outDir, { recursive: true });
fs.writeFileSync(path.join(outDir, 'index.html'), html);
fs.writeFileSync(path.join(outDir, 'cameraSession.js'), sessionJs);

const MEDIA = /video\/|image\/|data:(video|image)|filename=/i;
(async () => {
  const browser = await chromium.launch({ headless: true, args: ['--use-fake-device-for-media-stream', '--use-fake-ui-for-media-stream'] });
  const served = [], blocked = [], violations = [], sockets = [];
  try {
    const context = await browser.newContext();
    await context.grantPermissions(['camera'], { origin });
    await context.route('**/*', async (route) => {
      const request = route.request(), url = new URL(request.url());
      const body = request.postDataBuffer();
      const type = request.headers()['content-type'] || '';
      if (body?.length || MEDIA.test(type)) violations.push(`${request.method()} ${url.pathname} body=${body?.length ?? 0} type=${type || '-'}${body && MEDIA.test(body.toString('latin1')) ? ' (media/multipart field)' : ''}`);
      const file = url.origin === origin ? { '/': 'index.html', '/cameraSession.js': 'cameraSession.js' }[url.pathname] : undefined;
      if (!file || request.method() !== 'GET') { blocked.push(`${request.method()} ${request.url()}`); return route.abort(); }
      served.push(url.pathname);
      await route.fulfill({ path: path.join(outDir, file), contentType: file.endsWith('.js') ? 'text/javascript' : 'text/html' });
    });
    const page = await context.newPage();
    page.on('websocket', ws => sockets.push(ws.url()));
    await page.goto(`${origin}/`);
    await page.waitForFunction(() => !!window.__camera);
    assert.equal(await page.evaluate(() => window.__camera.state()), 'off', 'camera must not start on load');

    await page.click('#start');
    await page.waitForFunction(() => window.__camera.state() === 'on', null, { timeout: 10000 });
    const live = await page.evaluate(() => window.__camera.tracks());
    assert.deepEqual(live, [{ kind: 'video', readyState: 'live' }], 'exactly one live video track, no audio');
    await page.waitForFunction(() => document.getElementById('view').videoWidth > 0, null, { timeout: 10000 });
    await page.waitForTimeout(1000); // let any hypothetical upload fire

    await page.click('#stop');
    assert.equal(await page.evaluate(() => window.__camera.state()), 'off');
    assert.deepEqual(await page.evaluate(() => window.__camera.tracks()), [{ kind: 'video', readyState: 'ended' }], 'tracks ended after stop');
    assert.equal(await page.evaluate(() => document.getElementById('view').srcObject), null);

    assert.deepEqual(violations, [], 'no request carried a body or media payload');
    assert.deepEqual(blocked, [], 'no request beyond the static page and module');
    assert.deepEqual(sockets, [], 'no websocket opened');
    console.log(JSON.stringify({ ok: true, served, blocked: blocked.length, violations: violations.length, sockets: sockets.length }));
  } finally {
    await browser.close();
  }
})().catch((error) => { console.error(error); process.exit(1); });
