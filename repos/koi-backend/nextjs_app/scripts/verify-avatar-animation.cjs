const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const path = require('node:path');
const { chromium } = require('playwright');
const attachAudit = require('./avatar-browser-audit.cjs');
(async () => {
  const origin = 'http://127.0.0.1:3001';
  const output = path.resolve('dev/avatar-sandbox/.next/verification/increment-4');
  await fs.mkdir(output, { recursive: true });
  const browser = await chromium.launch({ headless: true, executablePath: process.env.KOI_AVATAR_BROWSER,
    args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    page.setDefaultTimeout(60000);
    const audit = await attachAudit(page, origin), requests = [];
    page.on('request', (request) => requests.push(request.url()));
    await page.addInitScript(() => {
      window.__avatarReadyEvents = [];
      window.addEventListener('AVATAR_READY', (event) => window.__avatarReadyEvents.push(event.detail));
    });
    const ready = (modelUrl = null) => page.waitForFunction((modelUrl) => window.AvatarController?.ready && (!modelUrl || window.AvatarController.getSnapshot().modelUrl === modelUrl), modelUrl, { timeout: 120000 });
    const snapshot = () => page.evaluate(() => window.AvatarController.getSnapshot());
    const emotion = async (name, intensity, preset) => {
      await page.evaluate(({ name, intensity }) => window.AvatarController.setEmotion(name, intensity), { name, intensity });
      await page.waitForFunction(({ preset, intensity }) => {
        const weights = window.AvatarController?.getSnapshot().animation?.weights;
        return weights && Object.entries(weights).every(([name, value]) => Math.abs(value - (name === preset ? intensity * 0.65 : 0)) < 0.001);
      }, { preset, intensity });
    };
    const shot = (name) => page.screenshot({ path: path.join(output, name + '.png') });
    // Queue a real command while the original model response is deliberately held.
    let release; const gate = new Promise((resolve) => { release = resolve; });
    await page.route('**/models/koi-male.vrm', async (route) => { await gate; await route.continue().catch(() => {}); });
    await page.goto(origin + '/companion-scene');
    await page.waitForFunction(() => !!window.AvatarController);
    assert.equal((await snapshot()).ready, false);
    await page.evaluate(() => window.AvatarController.setEmotion('joy', 0.7));
    release(); await ready(); await page.unroute('**/models/koi-male.vrm');
    await emotion('joy', 0.7, 'happy');
    const maleGeneration = (await snapshot()).generation;
    const mappings = { neutral: null, joy: 'happy', angry: 'angry', sorrow: 'sad', fun: 'relaxed' };
    for (const [name, preset] of Object.entries(mappings)) {
      await emotion(name, 1, preset); const value = await snapshot();
      assert(value.animation.availableEmotions.includes(name));
      assert(Object.values(value.animation.weights).filter((weight) => weight > 0.001).length <= 1);
      assert(Object.values(value.animation.mouthWeights).every((weight) => weight === 0));
      await shot('male-' + name);
    }
    await emotion('joy', 1, 'happy');
    const continuity = await page.evaluate(() => {
      const before = window.AvatarController.getSnapshot().animation.weights.happy;
      window.AvatarController.setEmotion('angry', 1);
      return { before, after: window.AvatarController.getSnapshot().animation.weights.happy };
    }); assert.equal(continuity.before, continuity.after);
    await page.waitForFunction(() => { const w = window.AvatarController.getSnapshot().animation.weights; return w.happy > 0 && w.happy < 0.65 && w.angry === 0; });
    await page.evaluate(() => { for (let index = 0; index < 100; index++) window.AvatarController.setEmotion(['joy', 'sorrow', 'angry', 'fun'][index % 4], (index % 11) / 10); });
    await emotion('fun', 0.7, 'relaxed');
    await emotion('joy', 0, null);
    await page.evaluate(() => window.AvatarController.setEmotion('unknown', NaN));
    assert.equal((await snapshot()).animation.emotion, 'neutral');
    await page.evaluate(() => window.AvatarController.setEmotion('joy', 100));
    await emotion('joy', 1, 'happy');
    await page.waitForFunction(() => window.AvatarController.getSnapshot().animation.blinkWeight > 0.9, null, { timeout: 10000 });
    const blink = await snapshot(); assert(blink.animation.weights.happy > 0.64); assert(Object.values(blink.animation.mouthWeights).every((weight) => weight === 0));
    const states = {};
    for (const state of ['idle', 'listening', 'thinking', 'speaking']) {
      await page.evaluate((state) => window.AvatarController.setConversationState(state), state);
      await page.waitForTimeout(800); states[state] = (await snapshot()).animation;
      assert.equal(states[state].conversationState, state); assert(Math.abs(states[state].chestOffset) <= 0.00151);
    }
    assert.notDeepEqual(states.listening.headRotation, states.thinking.headRotation);
    assert.notDeepEqual(states.idle.headRotation, states.speaking.headRotation);
    assert.equal(await page.evaluate(() => window.__avatarAudit.pending.size), 1);
    await page.emulateMedia({ reducedMotion: 'reduce' });
    await page.waitForFunction(() => window.AvatarController.getSnapshot().animation.reducedMotion);
    const reducedA = (await snapshot()).animation; await page.waitForTimeout(300); const reducedB = (await snapshot()).animation;
    assert.deepEqual(reducedA.headRotation, reducedB.headRotation); assert.equal(reducedB.chestOffset, 0);
    await page.emulateMedia({ reducedMotion: 'no-preference' });
    // Exercise the development controls, rather than only invoking the facade.
    await page.getByRole('button', { name: 'Preview settings' }).click();
    await page.getByLabel('KOI emotion', { exact: true }).selectOption('sorrow');
    await page.getByLabel('Emotion intensity', { exact: true }).focus();
    await page.keyboard.press('End'); for (let index = 0; index < 4; index++) await page.keyboard.press('ArrowLeft');
    await page.getByLabel('Conversation state', { exact: true }).selectOption('thinking');
    await page.waitForFunction(() => window.AvatarController.getSnapshot().animation.conversationState === 'thinking');
    await page.getByLabel('Preview model', { exact: true }).selectOption('female'); await ready('/models/koi-female.vrm');
    const femaleGeneration = (await snapshot()).generation; assert(femaleGeneration > maleGeneration);
    await page.getByRole('button', { name: 'Preview settings' }).click();
    for (const [name, preset] of Object.entries(mappings)) { await emotion(name, 1, preset); await shot('female-' + name); }
    await page.setViewportSize({ width: 390, height: 844 }); await page.waitForTimeout(300);
    await emotion('joy', 0.7, 'happy'); await shot('female-mobile-joy');
    assert.equal(await page.locator('canvas').count(), 1);
    assert(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth));
    await page.getByRole('button', { name: 'Preview settings' }).click();
    await page.getByRole('button', { name: 'Reset avatar' }).click();
    await page.waitForFunction(() => Object.values(window.AvatarController.getSnapshot().animation.weights).every((weight) => weight < 0.001));
    assert.equal((await snapshot()).animation.conversationState, 'idle');
    // Leave a female response pending, then switch back: stale loads must never bind.
    await page.getByLabel('Preview model', { exact: true }).selectOption('male'); await ready('/models/koi-male.vrm');
    let releaseStale; const staleGate = new Promise((resolve) => { releaseStale = resolve; });
    await page.route('**/models/koi-female.vrm', async (route) => { await staleGate; await route.continue().catch(() => {}); });
    await page.getByLabel('Preview model', { exact: true }).selectOption('female');
    await page.waitForFunction(() => !window.AvatarController.ready);
    await page.getByLabel('Preview model', { exact: true }).selectOption('male'); releaseStale(); await ready('/models/koi-male.vrm');
    await page.unroute('**/models/koi-female.vrm'); await page.waitForTimeout(300);
    assert.equal((await snapshot()).modelUrl, '/models/koi-male.vrm');
    assert.equal(await page.evaluate(() => window.__avatarAudit.contexts.filter((gl) => !gl.isContextLost()).length), 1);
    const events = await page.evaluate(() => window.__avatarReadyEvents);
    assert.equal(new Set(events.map((event) => event.generation)).size, events.length);
    await page.evaluate(() => { window.__retainedAvatar = window.AvatarController; });
    await page.getByRole('button', { name: 'Preview settings' }).click();
    await page.getByRole('button', { name: 'End conversation' }).click();
    await page.getByRole('heading', { name: 'KOI development sandbox' }).waitFor(); await page.waitForTimeout(300);
    const cleanup = await page.evaluate(() => {
      window.__retainedAvatar.setEmotion('joy', 1); window.__retainedAvatar.setConversationState('speaking'); window.__retainedAvatar.reset();
      return { globalRemoved: !window.AvatarController, staleLifecycle: window.__retainedAvatar.lifecycle,
        pendingFrames: window.__avatarAudit.pending.size, observers: window.__avatarAudit.observers.size,
        contexts: window.__avatarAudit.contexts.filter((gl) => !gl.isContextLost()).length, mediaCalls: window.__avatarAudit.mediaCalls };
    });
    assert.deepEqual(cleanup, { globalRemoved: true, staleLifecycle: 'disposed', pendingFrames: 0, observers: 0, contexts: 0, mediaCalls: 0 });
    assert.deepEqual(audit.errors, []); assert.deepEqual(audit.consoleErrors, []); assert.deepEqual(audit.external, []);
    assert(!requests.some((url) => /\/api\//.test(url)));
    const result = { passed: true, continuity, readyEvents: events, blinkWithJoy: blink.animation.blinkWeight,
      states, cleanup, ...audit };
    await fs.writeFile(path.join(output, 'results.json'), JSON.stringify(result, null, 2)); console.log(JSON.stringify(result, null, 2));
  } finally { await browser.close(); }
})().catch((error) => { console.error(error); process.exitCode = 1; });
