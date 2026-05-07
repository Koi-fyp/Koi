const { chromium } = require('playwright');
const path = require('path');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.setViewportSize({ width: 390, height: 844 }); // iPhone 14 Pro

  const BASE = 'http://localhost:3000';
  const OUT  = path.join(__dirname);

  const shots = [
    { url: '/',            name: '01_landing' },
    { url: '/onboarding',  name: '02_onboarding' },
    { url: '/chat',        name: '03_chat' },
    { url: '/progress',    name: '04_progress' },
    { url: '/settings',    name: '05_settings' },
  ];

  for (const { url, name } of shots) {
    await page.goto(BASE + url, { waitUntil: 'networkidle', timeout: 15000 });
    await page.waitForTimeout(800);
    await page.screenshot({ path: path.join(OUT, `${name}.png`), fullPage: false });
    console.log(`✓ ${name}.png`);
  }

  await browser.close();
})();
