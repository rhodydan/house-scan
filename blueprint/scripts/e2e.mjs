// End-to-end check of the html-in-canvas parts in real Chrome, against the dev server in HA_MOCK mode:
// a drawn room label opens its room's panel, and a tap on a drawn panel button changes the pretend device.
// Usage: node scripts/e2e.mjs [screenshot folder]
import { chromium } from 'playwright-core';

const base = 'http://127.0.0.1:5199';
const out = process.argv[2];
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
page.on('console', (m) => { if (m.type() === 'error') errors.push(m.text()); });
const settle = (ms) => page.waitForTimeout(ms);
const stateOf = async (id) => (await (await fetch(`${base}/ha/snapshot`)).json()).entities.find((e) => e.entity_id === id)?.state;
const result = {};

await page.goto(`${base}/?intro=0&live=0`);
await settle(6000);
await page.locator('.rail-item', { hasText: 'Main floor' }).click();
await settle(6000);
if (out) await page.screenshot({ path: `${out}/e2e-plan.png` });

// Click where the drawn Kitchen label appears on screen. Once a drawable element has geometry, Chrome reports its
// on-screen box through getBoundingClientRect, so its centre is where a person would tap. Chrome routes the click there.
const centre = (selector, text) => page.evaluate(([sel, t]) => {
  const el = [...document.querySelectorAll(sel)].find((e) => !t || e.textContent.startsWith(t));
  const r = el.getBoundingClientRect();
  return [r.left + r.width / 2, r.top + r.height / 2];
}, [selector, text]);
const labelAt = await centre('canvas > .room', 'Kitchen');
result.labelAt = labelAt;
await page.mouse.click(...labelAt);
await settle(6000);
result.panelOpen = await page.evaluate(() => document.querySelector('.control-panel h2')?.textContent);
if (out) await page.screenshot({ path: `${out}/e2e-room.png` });

// Pick the island pendants, then tap its drawn ON/OFF button.
const tap = async (selector) => {
  const at = await centre(selector);
  await page.mouse.click(...at);
  await settle(4000);
  return at;
};
await tap('[data-device="d2"]');
const before = await stateOf('switch.island_pendants');
await tap('[data-entity="switch.island_pendants"][data-service="toggle"]');
result.toggle = { before, after: await stateOf('switch.island_pendants') };
if (out) await page.screenshot({ path: `${out}/e2e-device.png` });
result.errors = errors.filter((e) => !/GPU stall|GL Driver/.test(e)).slice(0, 5);
console.log(JSON.stringify(result, null, 1));
await browser.close();
