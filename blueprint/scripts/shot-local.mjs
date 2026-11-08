// Screenshots of the local dashboard, for checking changes by eye. Usage: node scripts/shot-local.mjs <out folder> [query...]
import { chromium } from 'playwright-core';
const [out, ...queries] = process.argv.slice(2);
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
for (const [i, q] of queries.entries()) {
  await page.goto(`http://127.0.0.1:5199/?intro=0&live=0&${q}`);
  await page.waitForTimeout(11000);
  await page.screenshot({ path: `${out}/local-${i}.png` });
}
console.log(JSON.stringify({ errors }));
await browser.close();
