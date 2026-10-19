// Uses the existing avatar sandbox: npm run dev:avatar (port 3001).
const assert = require('node:assert/strict');
const { chromium } = require('playwright');

(async () => {
  const browser = await chromium.launch({ headless: true, executablePath: process.env.KOI_AVATAR_BROWSER });
  try {
    const page = await browser.newPage({ reducedMotion: 'reduce' });
    const errors = []; page.on('pageerror', error => errors.push(error.message));
    await page.goto('http://127.0.0.1:3001/environment-check');
    const call = page.locator('main[data-environment]'), chat = page.getByTestId('chat-surface');
    const click = name => page.getByRole('button', { name, exact: true }).click();
    await click('New turn');
    const expected = {
      neutral: ['#FFE5D9', '#FFE5D9'], joy: ['#FFE0A3', '#FFE2B8'], angry: ['#E0C3D3', '#EDD1D6'],
      sorrow: ['#CBC5DD', '#E0D2DC'], fun: ['#CBE1BF', '#E0E2C9'], calm: ['#C1D9D8', '#DADED8'],
    };
    const hex = rgb => '#' + rgb.match(/\d+/g).slice(0, 3).map(v => Number(v).toString(16).padStart(2, '0')).join('').toUpperCase();
    const color = locator => locator.evaluate(node => getComputedStyle(node).backgroundColor).then(hex);
    const ratios = [];
    for (const mood of ['neutral', 'joy', 'angry', 'sorrow', 'fun', 'calm']) {
      if (mood === 'calm') await click('Start fixture breathing'); else await click(mood);
      await page.waitForFunction(m => document.querySelector('main[data-environment]')?.dataset.environment === m, mood);
      assert.equal(await color(call), expected[mood][0]); assert.equal(await color(chat), expected[mood][1]);
      assert.equal(await call.evaluate(node => getComputedStyle(node).transitionDuration), '0s');
      // Measure the actual rendered foreground and composited ancestor surfaces.
      const measured = await page.locator('main[data-environment] p, main[data-environment] [role="log"] span, [data-testid="chat-surface"] [data-sender] div').evaluateAll(nodes => {
        const rgba = value => value.match(/[\d.]+/g).map(Number);
        const blend = (top, bottom) => { const a = top[3] ?? 1; return top.slice(0, 3).map((v, i) => v * a + bottom[i] * (1 - a)); };
        const lum = rgb => rgb.map(v => v / 255).map(v => v <= .04045 ? v / 12.92 : ((v + .055) / 1.055) ** 2.4).reduce((sum, v, i) => sum + v * [.2126, .7152, .0722][i], 0);
        return nodes.filter(node => [...node.childNodes].some(child => child.nodeType === Node.TEXT_NODE && child.textContent.trim()) && node.getClientRects().length).map(node => {
          const ancestors = []; for (let current = node; current; current = current.parentElement) ancestors.unshift(current);
          let bg = [255, 255, 255]; for (const ancestor of ancestors) bg = blend(rgba(getComputedStyle(ancestor).backgroundColor), bg);
          const fg = blend(rgba(getComputedStyle(node).color), bg), a = lum(fg), b = lum(bg);
          return { text: node.textContent.slice(0, 45), ratio: (Math.max(a, b) + .05) / (Math.min(a, b) + .05) };
        });
      });
      assert(measured.length); measured.forEach(result => assert(result.ratio >= 4.5, JSON.stringify({ mood, ...result })));
      ratios.push({ mood, minimumRenderedBodyContrast: Math.min(...measured.map(result => result.ratio)) });
    }
    await page.getByText('Activity complete', { exact: true }).waitFor();
    assert.equal(await call.getAttribute('data-environment'), 'fun');
    await click('HIGH fixture'); await page.getByRole('alertdialog').waitFor();
    await page.getByRole('button', { name: /misunderstanding/i }).click();
    assert.equal(await call.getAttribute('data-environment'), 'calm');
    await click('New turn'); assert.equal(await call.getAttribute('data-environment'), 'neutral');
    await click('fun'); assert.equal(await call.getAttribute('data-environment'), 'fun');
    await page.emulateMedia({ reducedMotion: 'no-preference' });
    assert.equal(await call.evaluate(node => getComputedStyle(node).transitionDuration), '1.8s');
    assert.equal(await call.evaluate(node => getComputedStyle(node).transitionTimingFunction), 'ease-in-out');
    const userBody = page.getByText('User body contrast fixture');
    assert.equal(await userBody.evaluate(node => getComputedStyle(node).color), 'rgb(0, 0, 0)');
    assert.equal(await userBody.evaluate(node => getComputedStyle(node).backgroundColor), 'rgb(59, 130, 246)');
    await page.reload(); assert.equal(await call.getAttribute('data-environment'), 'neutral');
    assert.deepEqual(await page.evaluate(() => ({ local: Object.keys(localStorage), session: Object.keys(sessionStorage) })), { local: [], session: [] });
    assert.deepEqual(errors, []);
    console.log(JSON.stringify({ passed: true, renderedSurfaces: 12, ratios, userBubbleContrast: 5.710, reducedMotion: true, resolutionReset: true, reloadReset: true }, null, 2));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
