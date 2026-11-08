// Drawing the lot by hand, in the site's plan view: lines (walls, paths, steps), areas (driveway, lawn, beds, patio,
// court, buildings, the property line), a pool, and outdoor places. Select a shape to drag its corners, rename it or
// delete it. Changes redraw at once; Save writes them into house.json through the dev server.
//
// The editor works in house.json's own frame (the stacked floors' frame); the drawing is centred on the house, so
// screen points are moved by `origin` on the way in and out.
import * as THREE from 'three';

const LINE_KINDS = ['wall', 'path', 'steps'];
const AREA_KINDS = ['driveway', 'lawn', 'bed', 'patio', 'court', 'structure', 'property'];
const NAMES = {
  wall: 'Wall', path: 'Path', steps: 'Steps', driveway: 'Driveway', lawn: 'Lawn', bed: 'Garden bed', patio: 'Patio',
  court: 'Court', structure: 'Building', property: 'Property line', pool: 'Pool',
};
const PICK_METRES = 1.2;
const CLICK_PIXELS = 5;

const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
const add = (a, b) => [a[0] + b[0], a[1] + b[1]];
const dist = (a, b) => Math.hypot(a[0] - b[0], a[1] - b[1]);
const round = (p) => [Math.round(p[0] * 100) / 100, Math.round(p[1] * 100) / 100];

function segmentDistance(p, a, b) {
  const d = sub(b, a), len2 = d[0] ** 2 + d[1] ** 2 || 1;
  const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * d[0] + (p[1] - a[1]) * d[1]) / len2));
  return dist(p, [a[0] + d[0] * t, a[1] + d[1] * t]);
}

function inside(p, poly) {
  let hit = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, zi] = poly[i], [xj, zj] = poly[j];
    if (zi > p[1] !== zj > p[1] && p[0] < ((xj - xi) * (p[1] - zi)) / (zj - zi) + xi) hit = !hit;
  }
  return hit;
}

export class SiteEditor {
  /**
   * scene, camera, canvas, controls: the dashboard's. origin: where the drawing's centre is in house.json's frame.
   * levels: { back, front } ground heights. site: house.json's site. onChange(site): redraw. onSave(site): persist.
   * onSheet(opacity): show the traced-over plan. areaNames(): Home Assistant area names, for naming places.
   */
  constructor({ scene, camera, canvas, controls, origin, levels, site, onChange, onSave, onSheet, areaNames }) {
    Object.assign(this, { scene, camera, canvas, controls, origin, levels, onChange, onSave, onSheet, areaNames });
    this.site = structuredClone(site ?? { features: [], places: [] });
    this.site.features ??= [];
    this.site.places ??= [];
    this.active = false;
    this.tool = 'select';
    this.kind = { line: 'wall', area: 'driveway' };
    this.level = 'back';
    this.points = [];
    this.selected = null;
    this.undoStack = [];
    this.dirty = false;
    this.overlay = new THREE.Group();
    this.overlay.renderOrder = 10;
    scene.add(this.overlay);
    this.buildToolbar();
    const host = canvas.parentElement;
    host.addEventListener('pointerdown', (e) => this.down(e), true);
    host.addEventListener('pointermove', (e) => this.move(e), true);
    host.addEventListener('pointerup', (e) => this.up(e), true);
    host.addEventListener('dblclick', (e) => { if (this.active) { e.stopPropagation(); this.finish(); } }, true);
    addEventListener('keydown', (e) => this.key(e));
  }

  // ---------- opening and closing ----------

  open() {
    if (this.active) return;
    this.active = true;
    this.saved = { left: this.controls.mouseButtons.LEFT, rotate: this.controls.enableRotate };
    // Left-drag pans instead of turning the plan; a click without a drag draws.
    this.controls.mouseButtons.LEFT = THREE.MOUSE.PAN;
    this.controls.enableRotate = false;
    this.toolbar.hidden = false;
    document.body.classList.add('editing-site');
    this.onSheet(Number(this.toolbar.querySelector('[name=sheet]').value));
    this.render();
  }

  close() {
    if (!this.active) return;
    if (this.dirty && !confirm('Leave without saving your site changes? They stay on screen until you reload.')) return;
    this.active = false;
    this.controls.mouseButtons.LEFT = this.saved.left;
    this.controls.enableRotate = this.saved.rotate;
    this.toolbar.hidden = true;
    document.body.classList.remove('editing-site');
    this.points = [];
    this.selected = null;
    this.onSheet(0);
    this.render();
  }

  // ---------- toolbar ----------

  buildToolbar() {
    const bar = document.createElement('div');
    bar.id = 'site-tools';
    bar.hidden = true;
    const options = (kinds) => kinds.map((k) => `<option value="${k}">${NAMES[k]}</option>`).join('');
    bar.innerHTML = `
      <div class="row tools">
        <button data-tool="select" class="on">Select</button>
        <button data-tool="line">Line</button><select name="line">${options(LINE_KINDS)}</select>
        <button data-tool="area">Area</button><select name="area">${options(AREA_KINDS)}</select>
        <button data-tool="pool">Pool</button>
        <button data-tool="place">Place</button>
      </div>
      <div class="row">
        <span>Ground</span><button data-level="back" class="on">Back yard</button><button data-level="front">Driveway side</button>
        <label>Plan sheet <input name="sheet" type="range" min="0" max="0.9" step="0.05" value="0.45"></label>
      </div>
      <div class="row">
        <button data-act="rename" disabled>Rename</button><button data-act="delete" disabled>Delete</button>
        <button data-act="undo" disabled>Undo</button><button data-act="save" disabled>Save</button><button data-act="done">Done</button>
      </div>
      <p class="hint"></p>`;
    bar.addEventListener('pointerdown', (e) => e.stopPropagation());
    bar.addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      if (b.dataset.tool) this.setTool(b.dataset.tool);
      if (b.dataset.level) { this.level = b.dataset.level; this.updateToolbar(); }
      if (b.dataset.act === 'rename') this.renameSelected();
      if (b.dataset.act === 'delete') this.deleteSelected();
      if (b.dataset.act === 'undo') this.undo();
      if (b.dataset.act === 'save') this.save();
      if (b.dataset.act === 'done') this.close();
    });
    bar.querySelector('[name=line]').onchange = (e) => { this.kind.line = e.target.value; this.setTool('line'); };
    bar.querySelector('[name=area]').onchange = (e) => { this.kind.area = e.target.value; this.setTool('area'); };
    bar.querySelector('[name=sheet]').oninput = (e) => this.onSheet(Number(e.target.value));
    document.body.appendChild(bar);
    this.toolbar = bar;
    this.updateToolbar();
  }

  setTool(tool) {
    this.tool = tool;
    this.points = [];
    this.poolCentre = null;
    if (tool !== 'select') this.selected = null;
    this.updateToolbar();
    this.render();
  }

  updateToolbar() {
    const bar = this.toolbar;
    bar.querySelectorAll('[data-tool]').forEach((b) => b.classList.toggle('on', b.dataset.tool === this.tool));
    bar.querySelectorAll('[data-level]').forEach((b) => b.classList.toggle('on', b.dataset.level === this.level));
    bar.querySelector('[data-act=rename]').disabled = !this.selected;
    bar.querySelector('[data-act=delete]').disabled = !this.selected;
    bar.querySelector('[data-act=undo]').disabled = !this.undoStack.length;
    bar.querySelector('[data-act=save]').disabled = !this.dirty;
    bar.querySelector('[data-act=save]').textContent = this.dirty ? 'Save' : 'Saved';
    const hints = {
      select: this.selected ? 'Drag a corner to move it. Delete removes the shape; Rename names it.' : 'Click a shape or place to select it. Drag to pan; scroll to zoom.',
      line: 'Click to add points. Double-click or Enter to finish; Esc cancels.',
      area: 'Click around the area. Double-click or Enter to close it; Esc cancels.',
      pool: this.poolCentre ? 'Click the edge of the pool.' : 'Click the centre of the pool.',
      place: 'Click where the place is, then name it after its Home Assistant area.',
    };
    bar.querySelector('.hint').textContent = hints[this.tool];
  }

  // ---------- pointer ----------

  /** The point on the ground under the pointer, in house.json's frame. */
  ground(e) {
    const rect = this.canvas.getBoundingClientRect();
    const pointer = new THREE.Vector2(((e.clientX - rect.left) / rect.width) * 2 - 1, -((e.clientY - rect.top) / rect.height) * 2 + 1);
    const ray = new THREE.Raycaster();
    ray.setFromCamera(pointer, this.camera);
    const hit = new THREE.Vector3();
    if (!ray.ray.intersectPlane(new THREE.Plane(new THREE.Vector3(0, 1, 0), -this.levels[this.level]), hit)) return null;
    return round(add([hit.x, hit.z], this.origin));
  }

  down(e) {
    if (!this.active || e.button !== 0 || e.target.closest('#site-tools')) return;
    this.pressed = { x: e.clientX, y: e.clientY };
    const p = this.ground(e);
    if (this.tool === 'select' && this.selected && p) {
      const handle = this.handles().findIndex((h) => dist(h, p) < PICK_METRES * 0.7);
      if (handle >= 0) {
        this.drag = { handle, before: JSON.stringify(this.site) };
        e.stopPropagation(); // no panning while a corner is dragged
      }
    }
  }

  move(e) {
    if (!this.active) return;
    const p = this.ground(e);
    if (!p) return;
    this.cursor = p;
    if (this.drag) { this.moveHandle(this.drag.handle, p); this.onChange(this.site); }
    this.render();
  }

  up(e) {
    if (!this.active || !this.pressed) return;
    const moved = Math.hypot(e.clientX - this.pressed.x, e.clientY - this.pressed.y);
    this.pressed = null;
    if (this.drag) {
      if (JSON.stringify(this.site) !== this.drag.before) { this.undoStack.push(this.drag.before); this.dirty = true; }
      this.drag = null;
      this.updateToolbar();
      return;
    }
    if (moved > CLICK_PIXELS || e.target.closest('#site-tools')) return;
    const p = this.ground(e);
    if (!p) return;
    if (this.tool === 'select') this.pick(p);
    else if (this.tool === 'line' || this.tool === 'area') { this.points.push(p); this.render(); }
    else if (this.tool === 'pool') {
      if (!this.poolCentre) { this.poolCentre = p; this.updateToolbar(); this.render(); }
      else { this.commit(() => this.site.features.push({ kind: 'pool', name: 'Pool', center: this.poolCentre, radius: Math.round(dist(p, this.poolCentre) * 100) / 100, elevation: this.levels[this.level] })); this.poolCentre = null; this.updateToolbar(); }
    } else if (this.tool === 'place') {
      const names = this.areaNames();
      const name = prompt(`Name this place after its Home Assistant area${names.length ? ` (${names.slice(0, 12).join(', ')}${names.length > 12 ? '…' : ''})` : ''}:`);
      if (name?.trim()) this.commit(() => this.site.places.push({ name: name.trim(), at: p, elevation: this.levels[this.level] }));
    }
  }

  key(e) {
    if (!this.active || e.target.closest?.('input, select, textarea')) return;
    if (e.key === 'Enter') this.finish();
    else if (e.key === 'Escape') { this.points = []; this.poolCentre = null; this.selected = null; this.updateToolbar(); this.render(); }
    else if ((e.key === 'Delete' || e.key === 'Backspace') && this.selected) { e.preventDefault(); this.deleteSelected(); }
    else if (e.key === 'z' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); this.undo(); }
  }

  // ---------- editing ----------

  finish() {
    const area = this.tool === 'area';
    // A double-click also lands two clicks on the same spot; drop the repeat.
    const pts = this.points.filter((p, i, all) => i === 0 || dist(p, all[i - 1]) > 0.05);
    this.points = [];
    if ((this.tool !== 'line' && !area) || pts.length < (area ? 3 : 2)) { this.render(); return; }
    const kind = area ? this.kind.area : this.kind.line;
    const name = prompt(`Name for this ${NAMES[kind].toLowerCase()} (optional):`, '') ?? '';
    const feature = { kind, points: pts, elevation: this.levels[this.level], closed: area };
    if (name.trim()) feature.name = name.trim();
    if (kind === 'structure') feature.height = Number(prompt('Height in metres:', '2.5')) || 2.5;
    this.commit(() => this.site.features.push(feature));
  }

  commit(change) {
    this.undoStack.push(JSON.stringify(this.site));
    change();
    this.dirty = true;
    this.onChange(this.site);
    this.updateToolbar();
    this.render();
  }

  undo() {
    const last = this.undoStack.pop();
    if (!last) return;
    this.site = JSON.parse(last);
    this.selected = null;
    this.dirty = true;
    this.onChange(this.site);
    this.updateToolbar();
    this.render();
  }

  pick(p) {
    let best = null;
    const consider = (type, index, d) => { if (d < PICK_METRES && (!best || d < best.d)) best = { type, index, d }; };
    this.site.places.forEach((pl, i) => consider('place', i, dist(pl.at, p) * 0.7));
    this.site.features.forEach((f, i) => {
      if (f.kind === 'pool') return consider('feature', i, Math.abs(dist(f.center, p) - f.radius));
      const pts = f.points ?? [];
      let d = Infinity;
      for (let k = 0; k < pts.length - 1 + (f.closed ? 1 : 0); k++) d = Math.min(d, segmentDistance(p, pts[k], pts[(k + 1) % pts.length]));
      // Inside a small closed area counts too, so beds and buildings are easy to grab.
      if (f.closed && pts.length > 2 && inside(p, pts) && f.kind !== 'property') d = Math.min(d, PICK_METRES * 0.9);
      consider('feature', i, d);
    });
    this.selected = best ? { type: best.type, index: best.index } : null;
    this.updateToolbar();
    this.render();
  }

  selectedThing() {
    if (!this.selected) return null;
    return this.selected.type === 'place' ? this.site.places[this.selected.index] : this.site.features[this.selected.index];
  }

  handles() {
    const t = this.selectedThing();
    if (!t) return [];
    if (this.selected.type === 'place') return [t.at];
    if (t.kind === 'pool') return [t.center, [t.center[0] + t.radius, t.center[1]]];
    return t.points ?? [];
  }

  moveHandle(i, p) {
    const t = this.selectedThing();
    if (this.selected.type === 'place') t.at = p;
    else if (t.kind === 'pool') { if (i === 0) t.center = p; else t.radius = Math.round(dist(p, t.center) * 100) / 100; }
    else t.points[i] = p;
  }

  renameSelected() {
    const t = this.selectedThing();
    if (!t) return;
    const name = prompt('Name:', t.name ?? '');
    if (name === null) return;
    this.commit(() => { if (name.trim()) t.name = name.trim(); else delete t.name; });
  }

  deleteSelected() {
    if (!this.selected) return;
    const { type, index } = this.selected;
    this.selected = null;
    this.commit(() => (type === 'place' ? this.site.places : this.site.features).splice(index, 1));
  }

  async save() {
    try {
      await this.onSave(this.site);
      this.dirty = false;
    } catch (error) {
      alert(`The site couldn't be saved: ${error.message}`);
    }
    this.updateToolbar();
  }

  // ---------- what the editor draws on top ----------

  render() {
    this.overlay.clear();
    if (!this.active) return;
    const y = this.levels[this.level] + 0.12;
    const at = (p) => new THREE.Vector3(p[0] - this.origin[0], y, p[1] - this.origin[1]);
    const ink = (color, opacity = 1) => new THREE.LineBasicMaterial({ color, transparent: true, opacity, depthTest: false });
    // The shape being drawn, with a rubber band to the pointer.
    const drawing = [...this.points, ...(this.cursor && this.points.length ? [this.cursor] : [])];
    if (this.tool === 'area' && drawing.length > 2) drawing.push(drawing[0]);
    if (drawing.length > 1) this.overlay.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(drawing.map(at)), ink(0xffd27a)));
    if (this.poolCentre && this.cursor) {
      const r = dist(this.cursor, this.poolCentre);
      const ring = Array.from({ length: 49 }, (_, i) => [this.poolCentre[0] + r * Math.cos((i / 48) * 2 * Math.PI), this.poolCentre[1] + r * Math.sin((i / 48) * 2 * Math.PI)]);
      this.overlay.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(ring.map(at)), ink(0xffd27a)));
    }
    // The selected shape, highlighted, with its corners as handles.
    const t = this.selectedThing();
    if (t && this.selected.type === 'feature' && t.points) {
      const pts = t.closed ? [...t.points, t.points[0]] : t.points;
      this.overlay.add(new THREE.Line(new THREE.BufferGeometry().setFromPoints(pts.map(at)), ink(0xffd27a)));
    }
    const handles = [...this.handles(), ...this.points];
    if (handles.length) {
      const dots = new THREE.Points(new THREE.BufferGeometry().setFromPoints(handles.map(at)),
        new THREE.PointsMaterial({ color: 0xffd27a, size: 9, sizeAttenuation: false, depthTest: false }));
      this.overlay.add(dots);
    }
  }
}
