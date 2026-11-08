import { defineConfig } from 'vite';
import { haBridge } from './server/ha-bridge.js';

// The house itself never lives in this repo. `HOUSE_DIR` points the dev server at a folder elsewhere that holds
// house.json and each floor's export; a build never includes it. Without it, the page asks for the files to be dropped in.
// The Home Assistant bridge runs only in the dev server, on this Mac: see server/ha-bridge.js.
//
// `vite build --mode demo` builds the public demo instead: the invented house in demo/, a pretend home in the browser,
// relative paths so it can live in any folder of a static site, and no server at all.
export default defineConfig(({ command, mode }) => {
  if (mode === 'demo') return { base: './', publicDir: 'demo', build: { outDir: 'dist-demo', emptyOutDir: true } };
  return {
    publicDir: command === 'serve' ? (process.env.HOUSE_DIR ?? false) : false,
    server: { host: '127.0.0.1', port: 5199, strictPort: true },
    plugins: [haBridge({ houseDir: process.env.HOUSE_DIR })],
  };
});
