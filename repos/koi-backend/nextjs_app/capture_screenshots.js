const { chromium } = require('playwright');
const path = require('path');

(async () => {
  const browser = await chromium.launch();
  const OUT = 'E:\\Koi\\Koi-App\\temporary_screenshots';
  const BASE = 'http://localhost:3000';

  // Chat — desktop, before messages
  {
    const page = await browser.newPage();
    await page.setViewportSize({ width: 760, height: 720 });
    await page.goto(`${BASE}/chat?preview=true`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(800);
    await page.screenshot({ path: path.join(OUT, '03_chat_desktop_before.png') });
    console.log('captured 03_chat_desktop_before.png');
    await page.close();
  }

  // Chat — desktop, inject mock messages then screenshot
  {
    const page = await browser.newPage();
    await page.setViewportSize({ width: 760, height: 720 });
    await page.goto(`${BASE}/chat?preview=true`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(600);

    // Type a message and "send" to trigger the after-chat state visually
    const textarea = await page.$('textarea');
    if (textarea) {
      await textarea.fill('Hey there! How can you help me today?');
      await page.waitForTimeout(300);
      await page.screenshot({ path: path.join(OUT, '03_chat_desktop_typing.png') });
      console.log('captured 03_chat_desktop_typing.png');
    }
    await page.close();
  }

  // Chat — mobile, before messages
  {
    const page = await browser.newPage();
    await page.setViewportSize({ width: 390, height: 844 });
    await page.goto(`${BASE}/chat?preview=true`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(800);
    await page.screenshot({ path: path.join(OUT, '03_chat_mobile_before.png') });
    console.log('captured 03_chat_mobile_before.png');
    await page.close();
  }

  // Progress + Settings desktop
  for (const { route, name } of [
    { route: '/progress', name: '04_progress_desktop' },
    { route: '/settings', name: '05_settings_desktop' },
  ]) {
    const page = await browser.newPage();
    await page.setViewportSize({ width: 760, height: 720 });
    await page.goto(`${BASE}${route}?preview=true`, { waitUntil: 'networkidle' });
    await page.waitForTimeout(800);
    await page.screenshot({ path: path.join(OUT, `${name}.png`) });
    console.log(`captured ${name}.png`);
    await page.close();
  }

  await browser.close();
})();
