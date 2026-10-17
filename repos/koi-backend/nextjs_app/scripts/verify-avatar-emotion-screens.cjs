// Rendered emotion verification on the display-only /avatar-host route (no Firebase, no API).
// One SwiftShader Chromium, reduced motion, 640x800. Models run one after the other.
// Usage: KOI_AVATAR_HOST_ORIGIN=http://127.0.0.1:3010 node scripts/verify-avatar-emotion-screens.cjs
const fs = require('node:fs/promises');
const path = require('node:path');
const { chromium } = require('playwright');

const ORIGIN = process.env.KOI_AVATAR_HOST_ORIGIN || 'http://127.0.0.1:3010';
const OUT = path.resolve(__dirname, '..', 'artifacts', 'avatar-emotion');
const MAX_WEIGHT = 0.65;
const PRESETS = { joy: 'happy', angry: 'angry', sorrow: 'sad', fun: 'relaxed' };
const EMOTIONS = ['neutral', 'joy', 'angry', 'sorrow', 'fun'];
const INTENSITIES = [0, 0.3, 0.7, 1.0];
const MODELS = { male: '/models/koi-male.vrm', female: '/models/koi-female.vrm' };
// Values observed from the live backend, replayed locally as fixtures (B2).
const LIVE_FIXTURES = [['sorrow', 0.7], ['joy', 0.3], ['neutral', 0.4]];
// The backend prompt asks for 0.2-0.7; the matrix lacks 0.2 and 0.5 (B3 / floor evidence).
const BACKEND_RANGE = Object.keys(PRESETS).flatMap((emotion) => [[emotion, 0.2], [emotion, 0.5]]);
const CHANGED_CHANNEL_DELTA = 16; // A pixel "changed" when any RGB channel moves by more than this.
const MIN_FIXED_CHANGED_FRACTION = 0.002; // Floor for "visibly differs from neutral" (0.2% of the face crop).

const expectedWeights = (emotion, intensity) => Object.fromEntries(Object.values(PRESETS)
  .map((preset) => [preset, emotion !== 'neutral' && PRESETS[emotion] === preset ? intensity * MAX_WEIGHT : 0]));
const isLocal = (url) => { try { const parsed = new URL(url); return ['data:', 'blob:', 'about:'].includes(parsed.protocol) || parsed.origin === ORIGIN; } catch { return false; } };
const id = (emotion, intensity) => `${emotion}-${String(intensity).replace('.', '_')}`;

async function analysisPage(context) {
  const page = await context.newPage();
  await page.setContent('<!doctype html><html><body style="margin:0;background:#fff;font:12px system-ui"></body></html>');
  await page.evaluate(() => {
    const decode = (b64) => new Promise((resolve, reject) => {
      const image = new Image();
      image.onload = () => {
        const canvas = document.createElement('canvas'); canvas.width = image.width; canvas.height = image.height;
        const ctx = canvas.getContext('2d', { willReadFrequently: true }); ctx.drawImage(image, 0, 0);
        resolve(ctx.getImageData(0, 0, image.width, image.height));
      };
      image.onerror = reject; image.src = 'data:image/png;base64,' + b64;
    });
    window.__stats = async (b64) => {
      const { data } = await decode(b64); let sum = 0, sq = 0; const n = data.length / 4;
      for (let i = 0; i < data.length; i += 4) { const l = 0.2126 * data[i] + 0.7152 * data[i + 1] + 0.0722 * data[i + 2]; sum += l; sq += l * l; }
      const mean = sum / n; return { mean, std: Math.sqrt(Math.max(0, sq / n - mean * mean)) };
    };
    // Temporal-noise mask in full-canvas coordinates: pixels that change between neutral frames captured over time
    // (e.g. secondary motion), dilated by 2 px. Masked pixels are excluded from every comparison.
    window.__noise = null;
    window.__buildNoiseMask = async (frames, delta) => {
      const images = await Promise.all(frames.map(decode));
      const { width, height } = images[0], raw = new Uint8Array(width * height), mask = new Uint8Array(width * height);
      for (const image of images.slice(1)) {
        for (let i = 0; i < image.data.length; i += 4) {
          const d = Math.max(Math.abs(image.data[i] - images[0].data[i]), Math.abs(image.data[i + 1] - images[0].data[i + 1]), Math.abs(image.data[i + 2] - images[0].data[i + 2]));
          if (d > delta) raw[i / 4] = 1;
        }
      }
      let count = 0, minX = Infinity, minY = Infinity, maxX = -1, maxY = -1;
      for (let y = 0; y < height; y++) for (let x = 0; x < width; x++) {
        let hit = 0;
        for (let dy = -2; dy <= 2 && !hit; dy++) for (let dx = -2; dx <= 2 && !hit; dx++) {
          const xx = x + dx, yy = y + dy;
          if (xx >= 0 && yy >= 0 && xx < width && yy < height && raw[yy * width + xx]) hit = 1;
        }
        if (hit) { mask[y * width + x] = 1; count++; minX = Math.min(minX, x); maxX = Math.max(maxX, x); minY = Math.min(minY, y); maxY = Math.max(maxY, y); }
      }
      window.__noise = { mask, width, height };
      const canvas = document.createElement('canvas'); canvas.width = width; canvas.height = height;
      const ctx = canvas.getContext('2d'); ctx.putImageData(images[0], 0, 0);
      const overlay = ctx.getImageData(0, 0, width, height);
      for (let p = 0; p < mask.length; p++) if (mask[p]) { overlay.data[p * 4] = 255; overlay.data[p * 4 + 1] = 0; overlay.data[p * 4 + 2] = 0; }
      ctx.putImageData(overlay, 0, 0);
      return { maskedFraction: count / (width * height), bbox: count ? { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1 } : null,
        heatmap: canvas.toDataURL('image/png').split(',')[1] };
    };
    // offset = crop origin inside the full canvas, used to look up the noise mask.
    window.__diff = async (a, b, delta, offset = { x: 0, y: 0 }) => {
      const [x, y] = await Promise.all([decode(a), decode(b)]);
      if (x.width !== y.width || x.height !== y.height) return { error: 'size mismatch' };
      const noise = window.__noise;
      let changed = 0, abs = 0, counted = 0, minX = Infinity, minY = Infinity, maxX = -1, maxY = -1;
      for (let i = 0; i < x.data.length; i += 4) {
        const p = i / 4, px = p % x.width, py = Math.floor(p / x.width);
        if (noise && noise.mask[(py + offset.y) * noise.width + (px + offset.x)]) continue;
        counted++;
        const d = Math.max(Math.abs(x.data[i] - y.data[i]), Math.abs(x.data[i + 1] - y.data[i + 1]), Math.abs(x.data[i + 2] - y.data[i + 2]));
        abs += d;
        if (d > delta) {
          changed++;
          minX = Math.min(minX, px); maxX = Math.max(maxX, px); minY = Math.min(minY, py); maxY = Math.max(maxY, py);
        }
      }
      const n = Math.max(1, counted);
      return { changedFraction: changed / n, meanAbs: abs / n, comparedPixels: counted,
        bbox: changed ? { x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1 } : null };
    };
    window.__sheet = (title, rows) => {
      document.body.innerHTML = '';
      const h = document.createElement('h2'); h.textContent = title; h.style.margin = '8px'; document.body.append(h);
      for (const row of rows) {
        const line = document.createElement('div'); line.style.cssText = 'display:flex;gap:6px;margin:6px 8px;align-items:flex-start';
        const label = document.createElement('div'); label.textContent = row.label; label.style.cssText = 'width:90px;font-weight:700;padding-top:4px';
        line.append(label);
        for (const cell of row.cells) {
          const figure = document.createElement('figure'); figure.style.margin = '0';
          const img = document.createElement('img'); img.src = 'data:image/png;base64,' + cell.b64; img.style.cssText = 'display:block;width:150px;border:1px solid #999';
          const caption = document.createElement('figcaption'); caption.textContent = cell.caption; caption.style.cssText = 'width:150px;white-space:pre-line';
          figure.append(img, caption); line.append(figure);
        }
        document.body.append(line);
      }
      return Promise.all([...document.images].map((img) => img.decode()));
    };
  });
  return page;
}

async function main() {
  await fs.mkdir(OUT, { recursive: true });
  const startedAt = Date.now();
  const browser = await chromium.launch({ headless: true, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  const failures = [];
  const fail = (message) => { failures.push(message); console.error('FAIL', message); };
  const result = { origin: ORIGIN, viewport: { width: 640, height: 800 }, reducedMotion: 'reduce', models: {}, blockedRequests: [] };
  try {
    const context = await browser.newContext({ viewport: { width: 640, height: 800 }, deviceScaleFactor: 1, reducedMotion: 'reduce' });
    await context.route('**/*', (route) => {
      if (isLocal(route.request().url())) return route.continue();
      result.blockedRequests.push(route.request().url()); return route.abort();
    });
    const analysis = await analysisPage(context);
    const page = await context.newPage();
    page.setDefaultTimeout(180000);
    const pageErrors = [], consoleErrors = [];
    page.on('pageerror', (error) => pageErrors.push(error.message));
    page.on('console', (message) => { if (message.type() === 'error') consoleErrors.push(message.text()); });
    await page.addInitScript(() => {
      window.__mediaCalls = 0;
      if (navigator.mediaDevices?.getUserMedia) navigator.mediaDevices.getUserMedia = async () => { window.__mediaCalls++; throw new Error('media disabled in this harness'); };
    });
    const cdp = await context.newCDPSession(page);
    await cdp.send('Performance.enable');
    const heapMb = async () => {
      const { metrics } = await cdp.send('Performance.getMetrics');
      const value = (name) => metrics.find((metric) => metric.name === name)?.value ?? 0;
      return { jsHeapUsedMb: +(value('JSHeapUsedSize') / 2 ** 20).toFixed(1), jsHeapTotalMb: +(value('JSHeapTotalSize') / 2 ** 20).toFixed(1) };
    };
    const snapshot = () => page.evaluate(() => window.AvatarController.getSnapshot());
    const frames = (count = 2) => page.evaluate((count) => new Promise((resolve) => {
      const step = (left) => left ? requestAnimationFrame(() => step(left - 1)) : resolve();
      step(count);
    }), count);
    const canvasBox = async () => {
      const box = await page.locator('canvas').boundingBox();
      if (!box) throw new Error('no canvas');
      return { x: Math.round(box.x), y: Math.round(box.y), width: Math.round(box.width), height: Math.round(box.height) };
    };

    // Applies one command, waits for exact settled weights and an open-eye window, then captures.
    async function capture(emotion, intensity, clip) {
      const t0 = Date.now();
      const accepted = await page.evaluate(([e, i]) => window.AvatarController.setEmotion(e, i), [emotion, intensity]);
      const expected = expectedWeights(emotion, intensity);
      await page.waitForFunction((expected) => {
        const weights = window.AvatarController.getSnapshot().animation.weights;
        return Object.entries(expected).every(([name, value]) => Math.abs((weights[name] ?? 0) - value) <= 1e-9);
      }, expected, { timeout: 30000 });
      const settleMs = Date.now() - t0;
      for (let attempt = 1; attempt <= 4; attempt++) {
        await page.waitForFunction(() => { const a = window.AvatarController.getSnapshot().animation; return a.blinkWeight === 0 && a.nextBlinkIn > 0.8; }, null, { timeout: 30000 });
        await frames(2);
        const before = (await snapshot()).animation;
        const buffer = await page.screenshot({ clip });
        const after = (await snapshot()).animation;
        // Valid only if no blink started or completed during the capture (countdown kept decreasing, eyes open).
        if (after.blinkWeight === 0 && before.blinkWeight === 0 && after.nextBlinkIn <= before.nextBlinkIn) {
          return { accepted, settleMs, captureMs: Date.now() - t0, attempts: attempt, b64: buffer.toString('base64'), buffer, animation: after, expected };
        }
      }
      throw new Error(`could not capture ${emotion}/${intensity} outside a blink`);
    }

    for (const [model, modelUrl] of Object.entries(MODELS)) {
      const modelResult = { modelUrl, cells: {}, liveFixtures: {}, backendRange: {} };
      result.models[model] = modelResult;
      const loadStart = Date.now();
      await page.goto(`${ORIGIN}/avatar-host?model=${model}`, { waitUntil: 'domcontentloaded' });
      await page.waitForFunction((url) => window.AvatarController?.ready === true && window.AvatarController.getSnapshot().modelUrl === url, modelUrl, { timeout: 180000 });
      modelResult.loadMs = Date.now() - loadStart;
      modelResult.heapAfterLoad = await heapMb();
      const initial = await snapshot();
      modelResult.availableEmotions = initial.animation.availableEmotions;
      if (JSON.stringify(initial.animation.availableEmotions) !== JSON.stringify(EMOTIONS)) fail(`${model}: availableEmotions ${initial.animation.availableEmotions}`);
      const full = await canvasBox();
      modelResult.canvas = full;

      // Temporal noise: four settled neutral frames about one second apart. Pixels that move between them are masked.
      const neutralFrames = [];
      for (let index = 0; index < 4; index++) {
        if (index) await page.waitForTimeout(1000);
        neutralFrames.push((await capture('neutral', 0, full)).b64);
      }
      const noise = await analysis.evaluate(([frames, d]) => window.__buildNoiseMask(frames, d), [neutralFrames, CHANGED_CHANNEL_DELTA]);
      await fs.writeFile(path.join(OUT, `${model}-noise-mask.png`), Buffer.from(noise.heatmap, 'base64'));
      modelResult.temporalNoiseMask = { maskedFractionOfCanvas: noise.maskedFraction, bbox: noise.bbox, file: `${model}-noise-mask.png` };

      // Calibrate the face crop: union of unmasked pixels that change between neutral and each emotion at 1.0.
      const neutralFull = await capture('neutral', 0, full);
      let union = null;
      for (const emotion of Object.keys(PRESETS)) {
        const shot = await capture(emotion, 1, full);
        const diff = await analysis.evaluate(([a, b, d]) => window.__diff(a, b, d), [neutralFull.b64, shot.b64, CHANGED_CHANNEL_DELTA]);
        if (!diff.bbox) { fail(`${model}: ${emotion}@1.0 produced no visible change on the full canvas`); continue; }
        union = union ? { x: Math.min(union.x, diff.bbox.x), y: Math.min(union.y, diff.bbox.y),
          x2: Math.max(union.x2, diff.bbox.x + diff.bbox.width), y2: Math.max(union.y2, diff.bbox.y + diff.bbox.height) }
          : { x: diff.bbox.x, y: diff.bbox.y, x2: diff.bbox.x + diff.bbox.width, y2: diff.bbox.y + diff.bbox.height };
      }
      if (!union) throw new Error(`${model}: no expression changed any pixel; cannot locate the face`);
      const margin = Math.round(Math.max(union.x2 - union.x, union.y2 - union.y) * 0.35);
      const left = Math.max(0, union.x - margin), top = Math.max(0, union.y - margin);
      const face = { x: full.x + left, y: full.y + top,
        width: Math.min(full.width - left, union.x2 - union.x + 2 * margin), height: Math.min(full.height - top, union.y2 - union.y + 2 * margin) };
      modelResult.faceClip = face;
      const offset = { x: face.x - full.x, y: face.y - full.y };
      if (face.width * face.height > 0.5 * full.width * full.height) fail(`${model}: face crop ${face.width}x${face.height} covers more than half the canvas`);
      await fs.writeFile(path.join(OUT, `${model}-full-neutral.png`), neutralFull.buffer);

      const neutralA = await capture('neutral', 0, face);
      const run = async (emotion, intensity, bucket) => {
        const shot = await capture(emotion, intensity, face);
        const name = `${model}-${id(emotion, intensity)}.png`;
        await fs.writeFile(path.join(OUT, name), shot.buffer);
        const stats = await analysis.evaluate((b64) => window.__stats(b64), shot.b64);
        const vsNeutral = await analysis.evaluate(([a, b, d, o]) => window.__diff(a, b, d, o), [neutralA.b64, shot.b64, CHANGED_CHANNEL_DELTA, offset]);
        const weightsOk = Object.entries(shot.expected).every(([preset, value]) => Math.abs(shot.animation.weights[preset] - value) <= 1e-9);
        const mouthZero = Object.values(shot.animation.mouthWeights).every((value) => value === 0);
        const cell = { file: name, accepted: shot.accepted, weights: shot.animation.weights, expected: shot.expected, weightsOk, mouthZero,
          snapshotEmotion: shot.animation.emotion, snapshotIntensity: shot.animation.intensity, lumaStd: +stats.std.toFixed(2),
          changedFraction: +vsNeutral.changedFraction.toFixed(5), meanAbsDiff: +vsNeutral.meanAbs.toFixed(3),
          settleMs: shot.settleMs, captureMs: shot.captureMs, attempts: shot.attempts, b64: shot.b64 };
        bucket[id(emotion, intensity)] = cell;
        if (!shot.accepted) fail(`${model} ${emotion}/${intensity}: setEmotion returned false`);
        if (!weightsOk) fail(`${model} ${emotion}/${intensity}: weights ${JSON.stringify(shot.animation.weights)} != ${JSON.stringify(shot.expected)}`);
        if (!mouthZero) fail(`${model} ${emotion}/${intensity}: mouth weights nonzero without speech`);
        if (stats.std < 8) fail(`${model} ${emotion}/${intensity}: face crop looks blank (luma std ${stats.std.toFixed(2)})`);
        return cell;
      };
      for (const emotion of EMOTIONS) for (const intensity of INTENSITIES) await run(emotion, intensity, modelResult.cells);
      for (const [emotion, intensity] of LIVE_FIXTURES) await run(emotion, intensity, modelResult.liveFixtures);
      for (const [emotion, intensity] of BACKEND_RANGE) await run(emotion, intensity, modelResult.backendRange);
      const neutralB = await capture('neutral', 0, face);
      const residual = await analysis.evaluate(([a, b, d, o]) => window.__diff(a, b, d, o), [neutralA.b64, neutralB.b64, CHANGED_CHANNEL_DELTA, offset]);
      modelResult.neutralNoise = { changedFraction: residual.changedFraction, meanAbsDiff: residual.meanAbs, comparedPixels: residual.comparedPixels };
      const visibleThreshold = Math.max(MIN_FIXED_CHANGED_FRACTION, 3 * residual.changedFraction);
      const sameTolerance = Math.max(0.0005, 2 * residual.changedFraction);
      modelResult.thresholds = { visibleChangedFraction: visibleThreshold, sameAsNeutralChangedFraction: sameTolerance };
      for (const emotion of EMOTIONS) {
        for (const intensity of INTENSITIES) {
          const cell = modelResult.cells[id(emotion, intensity)];
          if (emotion !== 'neutral' && intensity >= 0.7 && cell.changedFraction <= visibleThreshold) fail(`${model} ${emotion}/${intensity}: changed ${cell.changedFraction} <= visible threshold ${visibleThreshold}`);
          if ((emotion === 'neutral' || intensity === 0) && cell.changedFraction > sameTolerance) fail(`${model} ${emotion}/${intensity}: differs from neutral (${cell.changedFraction} > ${sameTolerance})`);
        }
      }
      const neutralFixture = modelResult.liveFixtures['neutral-0_4'];
      if (neutralFixture.changedFraction > sameTolerance) fail(`${model} live neutral/0.4 differs from neutral`);
      modelResult.heapAfterCells = await heapMb();

      const caption = (cell, label) => `${label}\nw=${Math.max(...Object.values(cell.weights)).toFixed(3)} Δ=${(cell.changedFraction * 100).toFixed(2)}%`;
      const rows = EMOTIONS.map((emotion) => ({ label: emotion, cells: INTENSITIES.map((intensity) => {
        const cell = modelResult.cells[id(emotion, intensity)]; return { b64: cell.b64, caption: caption(cell, `i=${intensity}`) };
      }) }));
      rows.push({ label: 'live fixtures', cells: LIVE_FIXTURES.map(([e, i]) => { const cell = modelResult.liveFixtures[id(e, i)]; return { b64: cell.b64, caption: caption(cell, `${e} ${i}`) }; }) });
      for (const emotion of Object.keys(PRESETS)) {
        rows.push({ label: `${emotion} 0.2-0.7`, cells: [0.2, 0.3, 0.5, 0.7].map((intensity) => {
          const cell = intensity === 0.2 || intensity === 0.5 ? modelResult.backendRange[id(emotion, intensity)] : modelResult.cells[id(emotion, intensity)];
          return { b64: cell.b64, caption: caption(cell, `i=${intensity}`) };
        }) });
      }
      await analysis.setViewportSize({ width: 820, height: 800 });
      await analysis.evaluate(([title, rows]) => window.__sheet(title, rows), [`KOI ${model} — /avatar-host, SwiftShader, reduced motion, 640x800 (Δ = face pixels changed vs neutral)`, rows]);
      await analysis.screenshot({ path: path.join(OUT, `contact-sheet-${model}.png`), fullPage: true });
      for (const bucket of [modelResult.cells, modelResult.liveFixtures, modelResult.backendRange]) for (const cell of Object.values(bucket)) delete cell.b64;
      console.log(`${model}: load ${modelResult.loadMs} ms, ${Object.keys(modelResult.cells).length + LIVE_FIXTURES.length + BACKEND_RANGE.length} cells`);
    }
    result.pageErrors = pageErrors;
    result.consoleErrors = consoleErrors;
    result.mediaCalls = await page.evaluate(() => window.__mediaCalls);
    if (pageErrors.length) fail(`page errors: ${pageErrors.join(' | ')}`);
    if (consoleErrors.length) fail(`console errors: ${consoleErrors.join(' | ')}`);
    if (result.blockedRequests.length) fail(`non-local requests attempted: ${result.blockedRequests.join(', ')}`);
    if (result.mediaCalls) fail('media permission requested');
    await context.close();
  } finally {
    await browser.close();
  }
  result.totalMs = Date.now() - startedAt;
  result.nodeRssMb = +(process.memoryUsage().rss / 2 ** 20).toFixed(1);
  result.failures = failures;
  result.passed = failures.length === 0;
  await fs.writeFile(path.join(OUT, 'emotion-screens-result.json'), JSON.stringify(result, null, 2));
  console.log(JSON.stringify({ passed: result.passed, failures, totalMs: result.totalMs, output: OUT }, null, 2));
  if (!result.passed) process.exitCode = 1;
}
main().catch((error) => { console.error(error); process.exitCode = 1; });
