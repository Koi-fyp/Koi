const assert = require('node:assert/strict'), fs = require('node:fs/promises'), path = require('node:path');
const { chromium } = require('playwright'), attachAudit = require('./avatar-browser-audit.cjs');
(async () => {
  const origin = 'http://127.0.0.1:3001', output = path.resolve('dev/avatar-sandbox/.next/verification/increment-6a'); await fs.mkdir(output, { recursive: true });
  const browser = await chromium.launch({ headless: true, executablePath: process.env.KOI_AVATAR_BROWSER, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } }), audit = await attachAudit(page, origin);
    await page.addInitScript(() => { const Original = window.Audio; window.__testAudio = []; window.Audio = class extends Original { constructor(...args) { super(...args); window.__testAudio.push(this); } }; });
    await page.goto(origin + '/speech-lab');
    const ready = () => page.waitForFunction(() => window.AvatarController?.ready && window.__koiSpeechLab, null, { timeout: 120000 }); await ready();
    const state = () => page.evaluate(() => window.__koiSpeechLab.getSnapshot().state);
    const zero = () => page.waitForFunction(() => Object.values(window.AvatarController.getSnapshot().animation.mouthWeights).every(value => value === 0));
    assert.equal(await state(), 'idle'); assert(await page.evaluate(() => window.__testAudio.every(audio => audio.paused)));
    const samples = [];
    async function collect(durationMs) {
      return page.evaluate(async (durationMs) => {
        const values = [], end = performance.now() + durationMs;
        while (performance.now() < end) {
          await new Promise(resolve => requestAnimationFrame(resolve));
          const frame = window.__koiSpeechLab.getFrame(), animation = window.AvatarController.getSnapshot().animation, applied = animation.speech;
          const cue = frame.cues.find(cue => applied.time >= cue.start && applied.time < cue.end), map = { A:null, B:'ih', C:'ee', D:'aa', E:'oh', F:'ou', G:'ih', H:'ee', X:null };
          let expected = 0; const preset = cue ? map[cue.value] : null;
          if (applied.active && preset) { const ramp = Math.min(.04, (cue.end - cue.start) / 2), t = Math.max(0, Math.min(1, (applied.time - cue.start) / ramp, (cue.end - applied.time) / ramp)); expected = .7 * t * t * (3 - 2 * t); }
          values.push({ audioTime: frame.time, appliedTime: applied.time, timeDifference: frame.time - applied.time, preset, expected, weights: animation.mouthWeights, blink: animation.blinkWeight, emotion: animation.emotion });
        } return values;
      }, durationMs);
    }
    await page.getByRole('button', { name: 'Play sample', exact: true }).click();
    await page.waitForFunction(() => window.__koiSpeechLab.getSnapshot().state === 'playing'); samples.push(...await collect(1300));
    await page.getByRole('button', { name: 'Pause', exact: true }).click(); await zero();
    const pausedAt = await page.evaluate(() => window.__koiSpeechLab.getFrame().time); await page.waitForTimeout(250);
    assert.equal(await page.evaluate(() => window.__koiSpeechLab.getFrame().time), pausedAt);
    await page.getByRole('button', { name: 'Resume', exact: true }).click(); await page.waitForFunction(() => window.__koiSpeechLab.getSnapshot().state === 'playing');
    await page.evaluate(() => window.__koiSpeechLab.seek(.45)); await page.waitForTimeout(100); samples.push(...await collect(300));
    await page.getByRole('button', { name: 'Stop', exact: true }).click(); await zero(); assert.equal(await page.evaluate(() => window.__koiSpeechLab.getFrame().time), 0);
    for (let i = 0; i < 3; i++) { await page.getByRole('button', { name: 'Play sample', exact: true }).click(); await page.getByRole('button', { name: 'Stop', exact: true }).click(); }
    await page.getByRole('button', { name: 'Play sample', exact: true }).click(); await page.waitForFunction(() => window.__koiSpeechLab.getSnapshot().state === 'playing');
    samples.push(...await collect(9000)); assert.equal(await state(), 'ended'); await zero();
    await page.getByRole('button', { name: 'Preview settings' }).click();
    for (const emotion of ['neutral', 'joy', 'angry', 'sorrow', 'fun']) {
      await page.getByLabel('Speech emotion').selectOption(emotion); await page.getByRole('button', { name: 'Play sample', exact: true }).click();
      await page.evaluate(() => window.__koiSpeechLab.seek(.45)); await page.waitForTimeout(250); samples.push(...await collect(150));
      assert.equal(await page.evaluate(() => window.AvatarController.getSnapshot().animation.emotion), emotion);
      await page.getByRole('button', { name: 'Stop', exact: true }).click(); await zero();
    }
    await page.getByRole('button', { name: 'Play sample', exact: true }).click();
    await page.getByLabel('Preview model', { exact: true }).selectOption('female'); await page.waitForFunction(() => window.AvatarController?.ready && window.AvatarController.getSnapshot().modelUrl.includes('female'));
    assert.equal(await state(), 'stopped'); await zero();
    await page.getByRole('button', { name: 'Preview settings' }).click();
    await page.getByRole('button', { name: 'Play sample', exact: true }).click(); samples.push(...await collect(1500));
    await page.screenshot({ path: path.join(output, 'desktop-speech.png') });
    await page.setViewportSize({ width: 390, height: 844 }); await page.waitForTimeout(250); assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    await page.screenshot({ path: path.join(output, 'mobile-speech.png') });
    await page.getByRole('button', { name: 'End conversation' }).click(); await page.getByRole('heading', { name: 'KOI development sandbox' }).waitFor(); await page.waitForTimeout(300);
    const cleanup = await page.evaluate(() => ({ frames: window.__avatarAudit.pending.size, observers: window.__avatarAudit.observers.size, contexts: window.__avatarAudit.contexts.filter(gl => !gl.isContextLost()).length, mediaCalls: window.__avatarAudit.mediaCalls,
      activeAudio: window.__testAudio.filter(audio => !audio.paused || audio.getAttribute('src')).length, diagnosticRemoved: !window.__koiSpeechLab }));
    assert.deepEqual(cleanup, { frames:0, observers:0, contexts:0, mediaCalls:0, activeAudio:0, diagnosticRemoved:true });
    await page.route('**/speech-fixture/speech-sample.wav', route => route.fulfill({ status:404, body:'Unavailable test fixture' }));
    await page.getByRole('link', { name: 'Open local speech lab' }).click(); await ready(); await page.getByRole('button', { name:'Play sample', exact:true }).click();
    await page.waitForFunction(() => window.__koiSpeechLab.getSnapshot().state === 'error'); await zero();
    await page.getByRole('button', { name:'Back to sandbox', exact:true }).click(); await page.getByRole('heading', { name:'KOI development sandbox' }).waitFor(); await page.waitForTimeout(300);
    assert(await page.evaluate(() => !window.__koiSpeechLab && window.__testAudio.every(audio => audio.paused && !audio.getAttribute('src')) && window.__avatarAudit.pending.size === 0 && window.__avatarAudit.observers.size === 0 && window.__avatarAudit.contexts.every(gl => gl.isContextLost())), 'failure exit must also dispose audio and rendering');
    const measured = samples.filter(sample => Number.isFinite(sample.appliedTime));
    for (const sample of measured) {
      for (const [name, value] of Object.entries(sample.weights)) assert(Math.abs(value - (name === sample.preset ? sample.expected : 0)) < 1e-7, 'mouth weights must match cue at actual consumed media time');
    }
    const differences = measured.map(sample => Math.abs(sample.timeDifference)).sort((a,b) => a-b);
    const sync = { samples:measured.length, maxObservedMediaClockDifferenceSeconds:differences.at(-1), p95ObservedMediaClockDifferenceSeconds:differences[Math.floor(differences.length*.95)], method:'Difference between current audio.currentTime and media time consumed by the last avatar frame; not acoustic/phoneme alignment latency.' };
    assert(measured.some(sample => sample.audioTime > .4 && sample.weights.aa > .4)); assert(measured.some(sample => sample.weights.ou > .4)); assert(measured.some(sample => sample.blink > .5));
    assert(sync.maxObservedMediaClockDifferenceSeconds < .5, 'unexpected frame/media lag');
    assert.deepEqual(audit.errors, []); // Deliberate 404 can produce a browser resource console error; report it separately.
    const unexpected = audit.consoleErrors.filter(message => !message.includes('404') && !message.includes('Failed to load resource')); assert.deepEqual(unexpected, []); assert.deepEqual(audit.external, []);
    const result = { passed:true, scope:'Real local media playback + authored fixture cues, NOT Rhubarb/Piper/backend speech', sync, cleanup, ...audit };
    await fs.writeFile(path.join(output, 'samples.json'), JSON.stringify(samples, null, 2)); await fs.writeFile(path.join(output,'results.json'), JSON.stringify(result,null,2)); console.log(JSON.stringify(result,null,2));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
