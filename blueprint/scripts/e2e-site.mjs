// Checks the site editor in real Chrome: draws a line, an area and a place with clicks, undoes once, saves, and reads
// house.json back. It SAVES, so run the dev server against a scratch copy of a house folder, never a real one:
//   HA_MOCK=1 HOUSE_DIR=<copy of demo/> npx vite   then   node scripts/e2e-site.mjs
import { chromium } from 'playwright-core';

const base = process.env.BASE ?? 'http://127.0.0.1:5199';
const browser = await chromium.launch({ channel: 'chrome', headless: true, args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const page = await browser.newPage({ viewport: { width: 1440, height: 900 } });
const errors = [];
page.on('pageerror', (e) => errors.push(e.message));
const answers = ['Test path', 'Test lawn', 'Kitchen'];
page.on('dialog', (d) => d.accept(d.type() === 'prompt' ? answers.shift() ?? '' : undefined));
const settle = (ms) => page.waitForTimeout(ms);
const read = async () => (await (await fetch(`${base}/house.json`, { cache: 'no-store' })).json()).site ?? { features: [], places: [] };
const before = await read();

await page.goto(`${base}/?intro=0&live=0`);
await settle(6000);
await page.locator('.rail-item', { hasText: 'Site' }).click();
await settle(5000);
await page.locator('#edit-site').click();
await settle(1500);
const result = { toolbar: await page.locator('#site-tools').isVisible() };
const click = async (x, y) => { await page.mouse.click(x, y); await settle(400); };

await page.locator('#site-tools [data-tool=line]').click();
await click(400, 300); await click(600, 320); await click(700, 420);
await page.keyboard.press('Enter'); await settle(800);
await page.locator('#site-tools select[name=area]').selectOption('lawn');
await click(420, 520); await click(620, 520); await click(620, 680); await click(420, 680);
await page.keyboard.press('Enter'); await settle(800);
await page.locator('#site-tools [data-tool=place]').click();
await click(520, 600); await settle(800);
await page.locator('#site-tools [data-tool=line]').click();
await click(300, 700); await click(350, 750);
await page.keyboard.press('Enter'); await settle(800); // a fourth shape, to be undone
await page.locator('#site-tools [data-act=undo]').click(); await settle(800);
await page.locator('#site-tools [data-act=save]').click(); await settle(1500);
const after = await read();
result.features = { before: before.features.length, after: after.features.length };
result.places = { before: before.places.length, after: after.places.length };
result.names = after.features.slice(-2).map((f) => `${f.kind}:${f.name}`).concat(after.places.slice(-1).map((p) => `place:${p.name}`));
result.saveButton = await page.locator('#site-tools [data-act=save]').textContent();
result.errors = errors;
console.log(JSON.stringify(result));
await browser.close();
