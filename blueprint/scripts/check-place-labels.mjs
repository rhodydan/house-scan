// Checks place lettering in the site editor: it stays upright after the plan sheet is shown and the site redrawn, and a
// new place's dot lands where it was clicked. Run against a scratch copy of a house folder (it doesn't save):
//   HA_MOCK=1 HOUSE_DIR=<copy> npx vite --port 5198   then   node scripts/check-place-labels.mjs <out dir>
import { chromium } from 'playwright-core';

const base = process.env.BASE ?? 'http://127.0.0.1:5198';
const out = process.argv[2] ?? '.';
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--enable-blink-features=CanvasDrawElement'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('dialog', (d) => d.accept(d.type() === 'prompt' ? 'Test place' : undefined));
const settle = (ms) => page.waitForTimeout(ms);
await page.goto(`${base}/?intro=0&live=0`);
await settle(6000);
const drawn = await page.evaluate(() => document.getElementById('scene').getAttribute('content') === 'drawable');
await page.locator('.rail-item', { hasText: 'Site' }).click();
await settle(5000);
await page.screenshot({ path: `${out}/1-site.png` });
await page.locator('#edit-site').click();
await settle(2500);
await page.screenshot({ path: `${out}/2-editing.png` });
await page.locator('#site-tools [data-tool=place]').click();
await page.mouse.click(720, 430);
await settle(2500);
await page.screenshot({ path: `${out}/3-new-place.png` });
// Where the new place's dot landed on screen, against the click.
const dot = await page.evaluate(() => {
  const el = [...document.querySelectorAll('.place')].find((e) => e.textContent.includes('Test place'));
  const r = el?.querySelector('i')?.getBoundingClientRect();
  return r ? [Math.round(r.x + r.width / 2), Math.round(r.y + r.height / 2)] : null;
});
// Select it, drag it, rename it: every step redraws the site.
await page.locator('#site-tools [data-tool=select]').click();
await page.mouse.click(720, 430);
await settle(800);
await page.mouse.move(720, 430);
await page.mouse.down();
for (let i = 1; i <= 15; i++) { await page.mouse.move(720 + i * 4, 430 + i * 2); await settle(30); }
await page.mouse.up();
await settle(1500);
await page.locator('#site-tools [data-act=rename]').click();
await settle(2500);
await page.screenshot({ path: `${out}/4-after-drag.png` });
console.log(JSON.stringify({ drawn, click: [720, 430], dot, errors }));
await browser.close();
