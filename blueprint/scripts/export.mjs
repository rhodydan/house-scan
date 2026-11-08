// Writes the assembled house to files for keeping: GLB, USDZ, OBJ and STL of the whole house, and a DXF plan per floor.
// Usage: node scripts/export.mjs <house folder> <output folder>
// The house folder holds house.json and each floor's House Scan JSON. Nothing is written inside this repo.
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { GLTFExporter } from 'three/examples/jsm/exporters/GLTFExporter.js';
import { OBJExporter } from 'three/examples/jsm/exporters/OBJExporter.js';
import { STLExporter } from 'three/examples/jsm/exporters/STLExporter.js';
import { USDZExporter } from 'three/examples/jsm/exporters/USDZExporter.js';
import { feetInches, loadHouse } from '../src/house.js';
import { buildSolidHouse } from '../src/solid.js';

// GLTFExporter reads its binary through FileReader, which Node doesn't have.
globalThis.FileReader ??= class {
  readAsArrayBuffer(blob) { blob.arrayBuffer().then((buffer) => { this.result = buffer; this.onloadend?.(); }); }
  readAsDataURL(blob) { blob.arrayBuffer().then((buffer) => { this.result = `data:${blob.type};base64,${Buffer.from(buffer).toString('base64')}`; this.onloadend?.(); }); }
};

const [houseDir, outDir] = process.argv.slice(2);
if (!houseDir || !outDir) {
  console.error('Usage: node scripts/export.mjs <house folder> <output folder>');
  process.exit(2);
}
const repo = path.resolve(import.meta.dirname, '..', '..');
if (path.resolve(outDir).startsWith(repo + path.sep)) {
  console.error('Refusing to write the house inside the repo.');
  process.exit(2);
}

const house = await loadHouse(async (name) => JSON.parse(await readFile(path.join(houseDir, name), 'utf8')));
const model = buildSolidHouse(house);
model.updateMatrixWorld(true);
await mkdir(outDir, { recursive: true });
const base = path.join(outDir, house.name.replace(/[^\w-]+/g, '-'));
const written = [];
const save = async (file, data) => { await writeFile(file, data); written.push(path.basename(file)); };

const glb = await new GLTFExporter().parseAsync(model, { binary: true });
await save(`${base}.glb`, Buffer.from(glb));
await save(`${base}.usdz`, Buffer.from(await new USDZExporter().parseAsync(model)));
await save(`${base}.obj`, new OBJExporter().parse(model));
const stl = new STLExporter().parse(model, { binary: true });
await save(`${base}.stl`, Buffer.from(stl.buffer));

// ---------- DXF: one plan per floor, metres, layers for walls, doors, windows, floor outline, furniture and room names ----------

function dxf(floor) {
  const out = ['0', 'SECTION', '2', 'HEADER', '9', '$INSUNITS', '70', '6', '9', '$MEASUREMENT', '70', '1', '0', 'ENDSEC'];
  const layers = { WALL: 7, DOOR: 30, WINDOW: 5, OPENING: 8, FLOOR: 8, FURNITURE: 9, ROOM: 2 };
  out.push('0', 'SECTION', '2', 'TABLES', '0', 'TABLE', '2', 'LAYER', '70', String(Object.keys(layers).length));
  for (const [name, color] of Object.entries(layers)) out.push('0', 'LAYER', '2', name, '70', '0', '62', String(color), '6', 'CONTINUOUS');
  out.push('0', 'ENDTAB', '0', 'ENDSEC', '0', 'SECTION', '2', 'ENTITIES');
  // DXF plans are drawn with Y up the page; the scan's Z runs down the page, so it's flipped to keep the plan unmirrored.
  const line = (layer, p, q) => out.push('0', 'LINE', '8', layer, '10', p[0].toFixed(4), '20', (-p[1]).toFixed(4), '30', '0',
    '11', q[0].toFixed(4), '21', (-q[1]).toFixed(4), '31', '0');
  const text = (layer, p, height, value) => out.push('0', 'TEXT', '8', layer, '10', p[0].toFixed(4), '20', (-p[1]).toFixed(4), '30', '0',
    '40', String(height), '1', value, '72', '1', '11', p[0].toFixed(4), '21', (-p[1]).toFixed(4), '31', '0');
  const at = (w, t) => [w.a[0] + w.along[0] * t, w.a[1] + w.along[1] * t];
  for (const w of floor.walls) {
    const n = [-w.along[1] * 0.055, w.along[0] * 0.055];
    let start = 0;
    const solid = (s, e) => {
      const p = at(w, s), q = at(w, e);
      line('WALL', [p[0] + n[0], p[1] + n[1]], [q[0] + n[0], q[1] + n[1]]);
      line('WALL', [p[0] - n[0], p[1] - n[1]], [q[0] - n[0], q[1] - n[1]]);
    };
    for (const g of w.gaps.filter((g) => g.to > g.from + 0.05)) {
      if (g.from > start) solid(start, g.from);
      const p = at(w, g.from), q = at(w, g.to);
      const layer = g.kind === 'door' ? 'DOOR' : g.kind === 'window' ? 'WINDOW' : 'OPENING';
      if (g.kind === 'window') {
        line(layer, [p[0] + n[0], p[1] + n[1]], [q[0] + n[0], q[1] + n[1]]);
        line(layer, [p[0] - n[0], p[1] - n[1]], [q[0] - n[0], q[1] - n[1]]);
        line(layer, p, q);
      } else {
        line(layer, p, q);
      }
      for (const end of [p, q]) line(g.kind === 'window' ? 'WALL' : layer, [end[0] + n[0], end[1] + n[1]], [end[0] - n[0], end[1] - n[1]]);
      start = Math.max(start, g.to);
    }
    if (w.length > start) solid(start, w.length);
  }
  floor.outline.forEach((p, i) => line('FLOOR', p, floor.outline[(i + 1) % floor.outline.length]));
  for (const o of floor.objects) {
    const c = (s, t) => [o.center[0] + o.along[0] * o.width / 2 * s + o.across[0] * o.depth / 2 * t,
      o.center[1] + o.along[1] * o.width / 2 * s + o.across[1] * o.depth / 2 * t];
    const ring = [c(-1, -1), c(1, -1), c(1, 1), c(-1, 1)];
    ring.forEach((p, i) => line('FURNITURE', p, ring[(i + 1) % 4]));
  }
  for (const r of floor.rooms) {
    text('ROOM', r.center, 0.25, r.name.toUpperCase());
    if (r.area) text('ROOM', [r.center[0], r.center[1] + 0.35], 0.15, `${Math.round(r.area * 10.7639)} SQ FT`);
  }
  out.push('0', 'ENDSEC', '0', 'EOF');
  return out.join('\n') + '\n';
}

for (const floor of house.floors) await save(`${base}-${floor.label.replace(/\s+/g, '-')}-plan.dxf`, dxf(floor));

const summary = house.floors.map((f) => `${f.label}: ${f.walls.length} walls, ${f.rooms.length} rooms, floor at ${feetInches(f.elevation)}`);
console.log(`Wrote ${written.length} files to ${outDir}:\n  ${written.join('\n  ')}\n${summary.join('\n')}`);
