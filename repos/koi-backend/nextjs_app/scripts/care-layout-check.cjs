// Offline static DOM previews from care-views.test.tsx. No app server or Firebase.
// Generate: KOI_CARE_PREVIEW_DIR=.local/care-ui-previews jest care-views.test.tsx
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const { chromium } = require('playwright');
const root = path.resolve(__dirname, '..');
const directory = path.join(root, '.local/care-ui-previews');
const output = path.join(directory, 'layout');
const cssDirectory = path.join(root, '.next/static/css');
// Prefer actual production CSS; no webfont/network loading is permitted.
const css = fs.existsSync(cssDirectory) ? fs.readdirSync(cssDirectory).filter(f => f.endsWith('.css')).map(f => fs.readFileSync(path.join(cssDirectory, f), 'utf8')).join('\n') : fs.readFileSync(path.join(root, 'src/app/globals.css'), 'utf8');
const careCss = fs.readFileSync(path.join(root, 'src/app/professional/professional.css'), 'utf8');
(async () => {
  const installed = ['C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe', 'C:/Program Files/Google/Chrome/Application/chrome.exe'].find(file => fs.existsSync(file));
  const browser = await chromium.launch({ headless: true, ...(installed ? { executablePath: installed } : {}) });
  const results = [];
  try {
    fs.mkdirSync(output, { recursive: true });
    const context = await browser.newContext({ offline: true, reducedMotion: 'reduce' });
    await context.route('**/*', route => route.abort());
    const page = await context.newPage();
    for (const file of fs.readdirSync(directory).filter(f => f.endsWith('.html'))) {
      for (const width of [390, 768, 1280, 1440]) {
        await page.setViewportSize({ width, height: 1000 });
        await page.setContent('<!doctype html><html lang="en"><head><meta charset="utf-8"><style>' + css + '\n' + careCss + '</style></head><body><div class="professional-shell"><main class="professional-main">' + fs.readFileSync(path.join(directory, file), 'utf8') + '</main></div></body></html>');
        // Open disclosures to include technical statuses and the AI drafting form layout.
        await page.locator('details').evaluateAll(elements => elements.forEach(e => { e.open = true; }));
        const layout = await page.evaluate(() => {
          const visible = el => el.getClientRects().length > 0;
          const controls = [...document.querySelectorAll('button,input:not([type=checkbox]),select,textarea,.care-sidebar a')].filter(visible);
          const clipped = controls.filter(el => { const r = el.getBoundingClientRect(); return r.left < -1 || r.right > innerWidth + 1; }).map(el => el.getAttribute('aria-label') || el.textContent.trim().slice(0, 80));
          const nav = document.querySelector('.care-sidebar');
          const content = document.querySelector('.care-content');
          return { width: innerWidth, documentWidth: document.documentElement.scrollWidth, clipped, sidebar: nav && content ? nav.getBoundingClientRect().right <= content.getBoundingClientRect().left : null, rtlFields: document.querySelectorAll('input[dir=rtl]').length };
        });
        assert.ok(layout.documentWidth <= width + 1, file + ' overflows at ' + width + ': ' + JSON.stringify(layout));
        assert.deepEqual(layout.clipped, [], file + ' has clipped controls at ' + width);
        if (layout.sidebar !== null) assert.equal(layout.sidebar, width >= 1100, file + ' sidebar breakpoint at ' + width);
        if (file === 'professional-questionnaires.html') assert.ok(layout.rtlFields > 0, 'Urdu fields retained');
        if ([390, 1440].includes(width) && ['professional-dashboard.html', 'professional-questionnaires.html', 'patient-home.html', 'review-failed.html'].includes(file)) await page.screenshot({ path: path.join(output, file.replace('.html', '-' + width + '.png')), fullPage: true });
        await page.keyboard.press('Tab');
        assert.ok(await page.evaluate(() => document.activeElement !== document.body), 'Keyboard focus available');
        results.push({ file, ...layout });
      }
    }
    assert.ok(results.length > 0, 'Static preview fixtures must exist');
    fs.writeFileSync(path.join(output, 'results.json'), JSON.stringify(results, null, 2));
    console.log(results.length + ' offline viewport checks passed at 390, 768, 1280 and 1440px.');
  } finally { await browser.close(); }
})().catch(error => { console.error(error.message); process.exitCode = 1; });
