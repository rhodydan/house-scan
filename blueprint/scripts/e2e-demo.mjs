// Checks the built public demo (dist-demo) the way a reader meets it, and takes the article's screenshots.
// Serve a folder whose demos/house-blueprint/ is dist-demo, then: node scripts/e2e-demo.mjs <base url> [screenshot folder]
import { chromium } from 'playwright-core';

const [base, out] = process.argv.slice(2);
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 860 }, deviceScaleFactor: 2 });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
const settle = (ms) => page.waitForTimeout(ms);
const centre = (selector, text) => page.evaluate(([sel, t]) => {
  const el = [...document.querySelectorAll(sel)].find((e) => !t || e.textContent.trim().startsWith(t));
  if (!el) return null;
  const r = el.getBoundingClientRect();
  return [r.left + r.width / 2, r.top + r.height / 2];
}, [selector, text]);
const result = {};

await page.goto(`${base}?intro=0`);
await settle(9000);
result.drawn = await page.evaluate(() => document.body.classList.contains('drawn'));
if (out) await page.screenshot({ path: `${out}/demo-overview.png` });

await page.locator('.rail-item', { hasText: 'Main floor' }).click();
await settle(7000);
await page.mouse.click(...(await centre('canvas > .room', 'Kitchen')));
await settle(6000);
result.panel = await page.evaluate(() => document.querySelector('.control-panel h2')?.textContent);
await page.mouse.click(...(await centre('[data-device]', 'Island pendants')));
await settle(4000);
const before = await page.evaluate(() => document.querySelector('[data-entity="switch.island_pendants"][data-service="toggle"]')?.textContent.trim());
await page.mouse.click(...(await centre('[data-entity="switch.island_pendants"][data-service="toggle"]')));
await settle(4000);
const after = await page.evaluate(() => document.querySelector('[data-entity="switch.island_pendants"][data-service="toggle"]')?.textContent.trim());
result.toggle = { before, after };
await page.mouse.click(...(await centre('[data-device]', 'Ceiling lights')));
await settle(5000);
if (out) await page.screenshot({ path: `${out}/demo-kitchen-panel.png` });

await page.mouse.click(...(await centre('canvas > .room', 'Hallway')));
await settle(6000);
await page.mouse.click(...(await centre('[data-device]', 'Thermostat')));
await settle(5000);
if (out) await page.screenshot({ path: `${out}/demo-thermostat.png` });

result.errors = errors.filter((e) => !/GPU stall|GL Driver|favicon|404/.test(e)).slice(0, 5);
console.log(JSON.stringify(result));
await browser.close();
