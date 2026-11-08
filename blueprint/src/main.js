import '@fontsource/architects-daughter';
import './style.css';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { CSS2DObject, CSS2DRenderer } from 'three/examples/jsm/renderers/CSS2DRenderer.js';
import { DrawnLayer, supported as drawnSupported } from './drawn.js';
import { DemoHome } from './demo-home.js';
import { Home } from './ha.js';
import { feetInches, loadHouse, placeSite, squareFeet } from './house.js';
import { renderPanel } from './panel.js';
import { SiteEditor } from './site-editor.js';
import { buildSite } from './site.js';

const PAPER = 0x10406f;
const WALL_THICKNESS = 0.11;
const FLOOR_GAP = 4.2; // metres between levels at full expand
const params = new URLSearchParams(location.search);
// html-in-canvas draws the lettering and the panel into the scene; without it they sit over the canvas as plain HTML.
const DRAWN = drawnSupported() && params.get('drawn') !== '0';

// ---------- loading ----------

async function readFromServer(name) {
  const response = await fetch(name, { cache: 'no-store' });
  if (!response.ok) throw new Error(`${name}: ${response.status}`);
  return response.json();
}

function readFromDrop() {
  const zone = document.getElementById('drop');
  zone.hidden = false;
  return new Promise((resolve) => {
    const take = async (fileList) => {
      const files = new Map();
      for (const file of fileList) files.set(file.name, JSON.parse(await file.text()));
      if (!files.has('house.json')) { zone.querySelector('p').textContent = 'No house.json among those files. Try again.'; return; }
      zone.hidden = true;
      resolve(async (name) => {
        if (!files.has(name)) throw new Error(`${name} wasn't dropped`);
        return files.get(name);
      });
    };
    zone.querySelector('input').addEventListener('change', (e) => take(e.target.files));
    addEventListener('dragover', (e) => e.preventDefault());
    addEventListener('drop', (e) => { e.preventDefault(); take(e.dataTransfer.files); });
  });
}

// ---------- linework ----------

/** Collects box edges and faces for one floor, so each floor is a handful of draw calls. */
class Sketch {
  lines = [];
  faces = [];
  glass = [];

  box(a, b, y0, y1, thickness, faces = this.faces) {
    const along = [b[0] - a[0], b[1] - a[1]];
    const len = Math.hypot(...along) || 1;
    const n = [(-along[1] / len) * thickness / 2, (along[0] / len) * thickness / 2];
    const c = [[a[0] + n[0], a[1] + n[1]], [b[0] + n[0], b[1] + n[1]], [b[0] - n[0], b[1] - n[1]], [a[0] - n[0], a[1] - n[1]]];
    const v = (i, y) => [c[i][0], y, c[i][1]];
    for (let i = 0; i < 4; i++) {
      const j = (i + 1) % 4;
      this.line(v(i, y0), v(j, y0));
      this.line(v(i, y1), v(j, y1));
      this.line(v(i, y0), v(i, y1));
      faces.push(...v(i, y0), ...v(j, y0), ...v(j, y1), ...v(i, y0), ...v(j, y1), ...v(i, y1));
    }
    faces.push(...v(0, y1), ...v(1, y1), ...v(2, y1), ...v(0, y1), ...v(2, y1), ...v(3, y1));
  }

  line(p, q) { this.lines.push(...p, ...q); }
}

const along = (w, t) => [w.a[0] + w.along[0] * t, w.a[1] + w.along[1] * t];

function sketchWall(sketch, w) {
  let start = 0;
  for (const g of w.gaps.filter((g) => g.to > g.from + 0.05)) {
    if (g.from > start + 0.01) sketch.box(along(w, start), along(w, g.from), w.bottom, w.top, WALL_THICKNESS);
    if (g.bottom > w.bottom + 0.03) sketch.box(along(w, g.from), along(w, g.to), w.bottom, g.bottom, WALL_THICKNESS);
    if (g.top < w.top - 0.03) sketch.box(along(w, g.from), along(w, g.to), Math.max(g.top, w.bottom), w.top, WALL_THICKNESS);
    if (g.kind === 'window') {
      sketch.box(along(w, g.from), along(w, g.to), g.bottom, g.top, 0.01, sketch.glass);
      const mid = along(w, (g.from + g.to) / 2);
      sketch.line([mid[0], g.bottom, mid[1]], [mid[0], g.top, mid[1]]);
    } else {
      const p = along(w, g.from), q = along(w, g.to);
      sketch.line([p[0], 0.005, p[1]], [q[0], 0.005, q[1]]);
    }
    start = Math.max(start, g.to);
  }
  if (w.length > start + 0.01) sketch.box(along(w, start), along(w, w.length), w.bottom, w.top, WALL_THICKNESS);
}

function hatchTexture() {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 64;
  const g = canvas.getContext('2d');
  g.strokeStyle = 'rgba(255,255,255,0.9)';
  g.lineWidth = 2;
  for (const o of [-64, 0, 64]) { g.beginPath(); g.moveTo(o, 64); g.lineTo(o + 64, 0); g.stroke(); }
  const texture = new THREE.CanvasTexture(canvas);
  texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(2.5, 2.5);
  texture.anisotropy = 4;
  return texture;
}

const geometryOf = (positions) => {
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  return g;
};

// ---------- lettering ----------

/**
 * A piece of lettering on the drawing. With html-in-canvas it's painted flat on the floor, so it tilts in perspective
 * like ink on the sheet and is still clickable; otherwise it floats over the canvas, always facing the viewer.
 */
function letter(group, html, className, at, { size = 1, onClick } = {}) {
  const element = document.createElement('div');
  element.className = className;
  element.innerHTML = html;
  if (onClick) {
    element.addEventListener('pointerdown', (e) => e.stopPropagation());
    element.addEventListener('click', (e) => { e.stopPropagation(); onClick(); });
  }
  if (DRAWN) {
    const surface = drawn.add(element, { metresPerPixel: 0.014 * size });
    surface.mesh.rotation.x = -Math.PI / 2; // lie flat, reading up the page (towards -Z)
    surface.mesh.position.set(at[0], at[1] + 0.02, at[2]);
    surface.mesh.renderOrder = 2;
    surface.interactive = Boolean(onClick);
    group.add(surface.mesh);
    return { element, surface, setOpacity: (o) => { surface.material.opacity = o; } };
  }
  const tag = new CSS2DObject(element);
  tag.position.set(...at);
  group.add(tag);
  return { element, tag, setOpacity: (o) => { element.style.opacity = String(o); element.style.pointerEvents = o > 0.5 && onClick ? 'auto' : 'none'; } };
}

const LEVELS = { 'Lower level': 0, 'Main floor': 1, Garage: 1, 'Upper floor': 2 };

function buildFloor(floor, index, hatch) {
  const group = new THREE.Group();
  group.name = floor.label;
  const sketch = new Sketch();
  floor.walls.forEach((w) => sketchWall(sketch, w));

  // Furniture and fixtures: dashed and faint, the way a survey shows what isn't built in.
  const dashed = [];
  for (const o of floor.objects) {
    const hw = o.width / 2, hd = o.depth / 2;
    const corner = (s, t) => [o.center[0] + o.along[0] * hw * s + o.across[0] * hd * t, o.center[1] + o.along[1] * hw * s + o.across[1] * hd * t];
    const ring = [corner(-1, -1), corner(1, -1), corner(1, 1), corner(-1, 1)];
    const top = o.category === 'stairs' ? 0.02 : o.bottom + o.height;
    for (let i = 0; i < 4; i++) {
      const p = ring[i], q = ring[(i + 1) % 4];
      dashed.push(p[0], top, p[1], q[0], top, q[1]);
      if (o.category !== 'stairs') dashed.push(p[0], o.bottom, p[1], p[0], top, p[1]);
    }
    if (o.category === 'stairs') {
      const treads = Math.max(2, Math.round(o.depth / 0.27));
      for (let i = 1; i < treads; i++) {
        const t = -1 + (2 * i) / treads;
        const p = corner(-1, t), q = corner(1, t);
        dashed.push(p[0], 0.02, p[1], q[0], 0.02, q[1]);
      }
    }
  }

  const materials = {
    line: new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.92 }),
    face: new THREE.MeshLambertMaterial({ color: 0xffffff, transparent: true, opacity: 0.13, side: THREE.DoubleSide, depthWrite: false }),
    glass: new THREE.MeshLambertMaterial({ color: 0xcfe8ff, transparent: true, opacity: 0.22, side: THREE.DoubleSide, depthWrite: false }),
    dashed: new THREE.LineDashedMaterial({ color: 0xffffff, transparent: true, opacity: 0.4, dashSize: 0.09, gapSize: 0.07 }),
    slab: new THREE.MeshBasicMaterial({ map: hatch, transparent: true, opacity: 0.1, side: THREE.DoubleSide, depthWrite: false }),
    outline: new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.55 }),
  };
  const base = Object.fromEntries(Object.entries(materials).map(([k, m]) => [k, m.opacity]));

  const lines = new THREE.LineSegments(geometryOf(sketch.lines), materials.line);
  group.add(lines);
  for (const [positions, material] of [[sketch.faces, materials.face], [sketch.glass, materials.glass]]) {
    const geometry = geometryOf(positions);
    geometry.computeVertexNormals();
    group.add(new THREE.Mesh(geometry, material));
  }
  const dashes = new THREE.LineSegments(geometryOf(dashed), materials.dashed);
  dashes.computeLineDistances();
  group.add(dashes);

  let slab = null;
  let anchor = [0, 0];
  if (floor.outline.length > 2) {
    const shape = new THREE.Shape(floor.outline.map(([x, z]) => new THREE.Vector2(x, z)));
    const geometry = new THREE.ShapeGeometry(shape);
    geometry.rotateX(Math.PI / 2);
    slab = new THREE.Mesh(geometry, materials.slab);
    slab.userData.floor = index;
    group.add(slab);
    const ring = floor.outline.flatMap((p, i) => { const q = floor.outline[(i + 1) % floor.outline.length]; return [p[0], 0, p[1], q[0], 0, q[1]]; });
    group.add(new THREE.LineSegments(geometryOf(ring), materials.outline));
    anchor = floor.outline.reduce((best, p) => (p[0] > best[0] ? p : best));
  }

  const points = floor.outline.length ? floor.outline : floor.walls.flatMap((w) => [w.a, w.b]);
  const bounds = {
    min: [Math.min(...points.map((p) => p[0])), Math.min(...points.map((p) => p[1]))],
    max: [Math.max(...points.map((p) => p[0])), Math.max(...points.map((p) => p[1]))],
  };

  // Room names, sized to fit their rooms, and notes.
  const labels = [];
  for (const room of floor.rooms) {
    const fit = room.area ? Math.min(1, Math.sqrt(room.area) / 3.2) : 1;
    const label = letter(group, `<b>${room.name}</b>${room.area ? `<span>${squareFeet(room.area)}</span>` : ''}`, 'room',
      [room.center[0], 0.08, room.center[1]], { size: Math.max(0.55, fit), onClick: () => openRoom(index, room) });
    label.small = (room.area ?? 0) < 4;
    labels.push(label);
  }
  for (const c of floor.callouts) labels.push(letter(group, `<span>${c.text}</span>`, 'note', [c.at[0], 0.05, c.at[1]], { size: 0.8 }));
  const garageDoor = floor.walls.flatMap((w) => w.gaps.filter((g) => g.label).map((g) => ({ w, g })))[0];
  if (garageDoor) {
    const mid = along(garageDoor.w, (garageDoor.g.from + garageDoor.g.to) / 2);
    const n = [-garageDoor.w.along[1], garageDoor.w.along[0]];
    const centre = [(bounds.min[0] + bounds.max[0]) / 2, (bounds.min[1] + bounds.max[1]) / 2];
    const out = (mid[0] - centre[0]) * n[0] + (mid[1] - centre[1]) * n[1] > 0 ? 1 : -1;
    labels.push(letter(group, `<span>${feetInches(garageDoor.g.to - garageDoor.g.from)} × ${feetInches(garageDoor.g.top - garageDoor.g.bottom)} ${garageDoor.g.label}</span><small>added by hand</small>`,
      'note', [mid[0] + n[0] * out * 1.1, 0.05, mid[1] + n[1] * out * 1.1], { size: 0.8 }));
  }

  const dims = buildDimensions(floor);
  dims.visible = false;
  group.add(dims);

  return { group, lines, materials, base, labels, dims, slab, anchor, bounds, level: LEVELS[floor.label] ?? index, alpha: 1, floor };
}

/** Dimension strings along the outside walls, with tick marks, set off the wall the way a draftsman does it. */
function buildDimensions(floor) {
  const group = new THREE.Group();
  if (floor.outline.length < 3) return group;
  const centroid = floor.outline.reduce((s, p) => [s[0] + p[0], s[1] + p[1]], [0, 0]).map((v) => v / floor.outline.length);
  const edgeDistance = (p) => Math.min(...floor.outline.map((a, i) => {
    const b = floor.outline[(i + 1) % floor.outline.length];
    const d = [b[0] - a[0], b[1] - a[1]];
    const len2 = d[0] ** 2 + d[1] ** 2 || 1;
    const t = Math.max(0, Math.min(1, ((p[0] - a[0]) * d[0] + (p[1] - a[1]) * d[1]) / len2));
    return Math.hypot(p[0] - a[0] - d[0] * t, p[1] - a[1] - d[1] * t);
  }));
  const segments = [];
  const tags = [];
  for (const w of floor.walls) {
    if (w.length < 1.4) continue;
    const mid = along(w, w.length / 2);
    if (edgeDistance(mid) > 0.45) continue;
    let n = [-w.along[1], w.along[0]];
    if ((mid[0] - centroid[0]) * n[0] + (mid[1] - centroid[1]) * n[1] < 0) n = [-n[0], -n[1]];
    const off = (p, d) => [p[0] + n[0] * d, 0.02, p[1] + n[1] * d];
    segments.push(...off(w.a, 0.15), ...off(w.a, 0.85), ...off(w.b, 0.15), ...off(w.b, 0.85), ...off(w.a, 0.7), ...off(w.b, 0.7));
    for (const p of [w.a, w.b]) {
      const c = off(p, 0.7);
      const tick = [(w.along[0] + n[0]) * 0.1, (w.along[1] + n[1]) * 0.1];
      segments.push(c[0] - tick[0], 0.02, c[2] - tick[1], c[0] + tick[0], 0.02, c[2] + tick[1]);
    }
    const label = letter(group, feetInches(w.length), 'dim', off(mid, 1.05), { size: 0.75 });
    if (label.surface) {
      // Lettering runs along the wall, turned so it never reads upside down.
      let turn = Math.atan2(-w.along[1], w.along[0]);
      if (Math.abs(turn) > Math.PI / 2) turn -= Math.sign(turn) * Math.PI;
      label.surface.mesh.rotation.z = turn;
    }
    tags.push(label);
  }
  group.add(new THREE.LineSegments(geometryOf(segments), new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.7 })));
  group.userData.tags = tags;
  return group;
}

// ---------- scene ----------

const canvas = document.getElementById('scene');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true, alpha: true });
renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
renderer.setClearColor(0x000000, 0);
const overlay = new CSS2DRenderer({ element: document.getElementById('labels') });
const scene = new THREE.Scene();
const camera = new THREE.PerspectiveCamera(28, 1, 0.1, 800);
const drawn = DRAWN ? new DrawnLayer(renderer, camera) : null;
const controls = new OrbitControls(camera, canvas);
controls.enableDamping = true;
controls.dampingFactor = 0.08;
controls.maxPolarAngle = Math.PI * 0.49;
// Embedded in an article, the wheel should scroll the page until the reader clicks into the drawing.
const EMBED = params.has('embed');
if (EMBED) {
  controls.enableZoom = false;
  document.body.classList.add('embed');
  canvas.addEventListener('pointerdown', () => { controls.enableZoom = true; document.body.classList.add('engaged'); }, { once: true });
}
scene.add(new THREE.AmbientLight(0xffffff, 0.55));
const sun = new THREE.DirectionalLight(0xffffff, 1.4);
sun.position.set(-6, 12, 9);
scene.add(sun);
document.body.classList.toggle('drawn', DRAWN);

const state = {
  view: 'axon', floors: [], expand: 1, expandTarget: 0.6, focus: null, hidden: new Set(), labels: true, spin: false,
  tween: null, intro: 0, radius: 30, north: null,
};
const ui = { open: false, floor: null, room: null, device: null, confirm: null, choosingArea: false, cameraTick: 0, error: null, sameName: 1 };
// The public demo (vite build --mode demo, or ?demo) runs a pretend home in the browser.
const DEMO = import.meta.env.MODE === 'demo' || params.has('demo');
const home = DEMO ? new DemoHome() : new Home();
ui.cameraUrl = (id, tick) => home.cameraUrl(id, tick);

function resize() {
  const { clientWidth: w, clientHeight: h } = canvas.parentElement;
  renderer.setSize(w, h, false);
  overlay.setSize(w, h);
  camera.aspect = w / h;
  camera.updateProjectionMatrix();
}
addEventListener('resize', resize);

// ---------- views ----------

// Plan uses a long lens from far away, so it reads as a flat drawing; the others keep some perspective.
const VIEWS = {
  axon: { polar: 0.95, azimuth: 0.62, fov: 28 },
  plan: { polar: 0.0001, azimuth: 0, fov: 9 },
  side: { polar: 1.45, azimuth: 0.0, fov: 22 },
};
const lensDistance = (fov) => Math.tan((28 * Math.PI) / 360) / Math.tan((fov * Math.PI) / 360);

/** The middle of the stack and how far back to stand to see it, at the current expand. */
function framing(expand = state.expandTarget) {
  const top = Math.max(3, ...state.floors.map((f) => f.floor.elevation + expand * f.level * FLOOR_GAP + 3));
  const narrow = Math.max(1, 1 / camera.aspect) ** 0.85;
  const room = params.has('embed') ? 1.3 : 1; // a small frame in an article needs more room around the house
  return { target: new THREE.Vector3(0, top / 2, 0), radius: state.radius * (1 + 0.45 * expand) * narrow * room };
}

function overview(name = 'axon') {
  const v = VIEWS[name];
  state.view = name;
  state.focus = null;
  closePanel();
  const { target, radius } = framing();
  state.tween = { polar: v.polar, azimuth: v.azimuth, fov: v.fov, radius: radius * lensDistance(v.fov), target };
  renderChrome();
}

/** One floor, straight down, filling the screen. With the panel open, the frame widens to fit it beside the plan. */
function planOf(index) {
  state.focus = index;
  state.view = 'plan';
  frameFocus();
  renderChrome();
}

/** The part of the screen the plan can use: clear of the controls at the top left and the floor rail on the right. */
function clearArea() {
  const W = canvas.clientWidth, H = canvas.clientHeight;
  const railBox = rail.getBoundingClientRect();
  const head = document.querySelector('header.panel').getBoundingClientRect();
  const right = railBox.width && railBox.left > W / 2 ? W - railBox.left + 16 : 24;
  const top = head.bottom < H / 2 ? head.bottom + 12 : 24;
  return { left: 24, top, width: Math.max(200, W - 24 - right), height: Math.max(200, H - top - 24) };
}

/** Metres per screen pixel that fit `width` x `depth` metres into the clear area. */
const fitScale = (width, depth, area) => Math.max(width / area.width, depth / area.height) * 1.08;

function frameFocus() {
  const f = state.floors[state.focus];
  if (!f) return;
  // The dimension strings sit about a metre outside the walls.
  const min = [f.bounds.min[0] - 1.4, f.bounds.min[1] - 1.4], max = [f.bounds.max[0] + 1.4, f.bounds.max[1] + 1.4];
  if (ui.open && panelMesh?.visible) {
    const p = panelMesh.position, s = panelMesh.scale;
    min[0] = Math.min(min[0], p.x - s.x / 2); max[0] = Math.max(max[0], p.x + s.x / 2);
    min[1] = Math.min(min[1], p.z - s.y / 2); max[1] = Math.max(max[1], p.z + s.y / 2);
  }
  const area = clearArea();
  const W = canvas.clientWidth, H = canvas.clientHeight;
  const perPixel = fitScale(max[0] - min[0], max[1] - min[1], area);
  const fov = VIEWS.plan.fov;
  const distance = (perPixel * H) / (2 * Math.tan((fov * Math.PI) / 360));
  // Put the middle of the content in the middle of the clear area, not the middle of the screen.
  const shiftX = (area.left + area.width / 2 - W / 2) * perPixel, shiftZ = (area.top + area.height / 2 - H / 2) * perPixel;
  const y = f.group.position.y;
  state.tween = { polar: VIEWS.plan.polar, azimuth: 0, fov, radius: distance,
                  target: new THREE.Vector3((min[0] + max[0]) / 2 - shiftX, y, (min[1] + max[1]) / 2 - shiftZ) };
}

// ---------- the panel ----------

const panel = document.createElement('div');
panel.className = 'control-panel';
panel.addEventListener('pointerdown', (e) => e.stopPropagation());
let panelSurface = null;
let panelMesh = null;
if (DRAWN) {
  panelSurface = drawn.add(panel, { metresPerPixel: 0.02 });
  panelMesh = panelSurface.mesh;
  panelMesh.rotation.x = -Math.PI / 2;
  panelMesh.renderOrder = 3;
  panelMesh.visible = false;
  panelSurface.material.opacity = 1;
  panelSurface.onResize = () => placePanel();
  scene.add(panelMesh);
} else {
  panel.classList.add('side');
  document.body.appendChild(panel);
}

/** Lays the panel on the sheet to the right of the floor plan, at about one screen pixel per CSS pixel. */
function placePanel() {
  if (!panelMesh || state.focus === null) return;
  const f = state.floors[state.focus];
  const depth = f.bounds.max[1] - f.bounds.min[1], width = f.bounds.max[0] - f.bounds.min[0];
  // Leave the plan about 55% of the clear width, so plan and panel fit side by side at about 1:1.
  const area = clearArea();
  const screenMetres = fitScale(width, depth, { ...area, width: area.width * 0.55 });
  panelSurface.setScale(screenMetres);
  const [w, h] = panelSurface.size.css;
  panelMesh.position.set(f.bounds.max[0] + 1.2 + (w * screenMetres) / 2, f.group.position.y + 0.05, f.bounds.min[1] + (h * screenMetres) / 2);
  if (ui.open) frameFocus();
}

function openRoom(index, room) {
  if (siteEditor?.active) return; // while drawing, a tap on a place label is a drawing tap
  ui.open = true;
  document.body.classList.add('room-open');
  ui.floor = state.floors[index].floor;
  ui.room = room;
  ui.device = null;
  ui.confirm = null;
  ui.choosingArea = false;
  ui.error = null;
  ui.sameName = state.floors.flatMap((f) => f.floor.rooms).filter((r) => r.name === room.name).length;
  if (state.focus !== index || state.view !== 'plan') planOf(index);
  drawPanel();
  placePanel();
  if (panelMesh) panelMesh.visible = true;
  frameFocus();
}

function closePanel() {
  ui.open = false;
  document.body.classList.remove('room-open');
  panel.hidden = !DRAWN;
  if (panelMesh) panelMesh.visible = false;
}

function drawPanel() {
  if (!ui.open) return;
  panel.hidden = false;
  panel.innerHTML = renderPanel(ui, home);
}

panel.addEventListener('click', async (e) => {
  const t = e.target.closest('button');
  if (!t) return;
  if (t.dataset.close !== undefined) { closePanel(); frameFocus(); return; }
  if (t.dataset.rechoose !== undefined) { ui.choosingArea = true; return drawPanel(); }
  if (t.dataset.area !== undefined) { ui.choosingArea = false; await home.chooseArea(ui.floor.label, ui.room.name, t.dataset.area || null); return; }
  if (t.dataset.device) { ui.device = ui.device === t.dataset.device ? null : t.dataset.device; ui.confirm = null; return drawPanel(); }
  if (t.dataset.service) {
    const { entity, service } = t.dataset;
    if (service === 'unlock' && ui.confirm !== entity) {
      ui.confirm = entity;
      setTimeout(() => { if (ui.confirm === entity) { ui.confirm = null; drawPanel(); } }, 4000);
      return drawPanel();
    }
    ui.confirm = null;
    ui.error = null;
    try { await home.call(entity, service, JSON.parse(t.dataset.data || '{}')); } catch (error) { ui.error = `That didn't work: ${error.message}`; }
    drawPanel();
  }
});
home.addEventListener('change', () => drawPanel());
setInterval(() => { if (ui.open && panel.querySelector('img.cam')) { ui.cameraTick++; drawPanel(); } }, 10000);

// ---------- chrome: floor rail, controls, north arrow ----------

const rail = document.getElementById('rail');
const leaders = document.getElementById('leaders');

function renderChrome() {
  rail.innerHTML = '';
  const whole = document.createElement('button');
  whole.className = `rail-item whole ${state.focus === null ? 'on' : ''}`;
  whole.innerHTML = '<b>Whole house</b><span>All floors</span>';
  whole.onclick = () => overview('axon');
  rail.appendChild(whole);
  [...state.floors.keys()].sort((a, b) => state.floors[b].floor.elevation - state.floors[a].floor.elevation).forEach((i) => {
    const f = state.floors[i];
    const b = document.createElement('button');
    b.className = `rail-item ${state.focus === i ? 'on' : ''} ${state.hidden.has(i) ? 'off' : ''}`;
    b.dataset.floor = i;
    b.innerHTML = f.site
      ? '<b>Site</b><span>Lot, landscape, outside · PLAN</span>'
      : `<b>${f.floor.label}</b><span>EL. ${f.floor.elevation >= 0 ? '+' : ''}${feetInches(f.floor.elevation)} · PLAN</span>`;
    b.onclick = () => { closePanel(); planOf(i); };
    rail.appendChild(b);
  });
  document.querySelectorAll('[data-view]').forEach((b) => b.classList.toggle('on', state.focus === null && b.dataset.view === state.view));
  // Editing the site is offered in the site's own plan, when there's a server to save to.
  const editButton = document.getElementById('edit-site');
  editButton.hidden = !siteEditor || !state.floors[state.focus]?.site;
  editButton.onclick = () => { closePanel(); siteEditor.open(); };
  if (siteEditor?.active && !state.floors[state.focus]?.site) siteEditor.close();
}

function wireControls() {
  document.querySelectorAll('[data-view]').forEach((b) => {
    b.onclick = () => (b.dataset.view === 'plan' ? planOf(state.focus ?? mainFloor()) : overview(b.dataset.view));
  });
  const expand = document.getElementById('expand');
  expand.oninput = () => { state.expandTarget = Number(expand.value); if (state.focus === null) overview(state.view === 'plan' ? 'axon' : state.view); };
  document.getElementById('spin').onclick = (e) => { state.spin = !state.spin; e.currentTarget.classList.toggle('on', state.spin); };
  document.getElementById('lettering').onclick = (e) => { state.labels = !state.labels; e.currentTarget.classList.toggle('on', state.labels); };
  document.getElementById('reset').onclick = () => { state.hidden.clear(); state.expandTarget = 0.6; expand.value = 0.6; overview('axon'); };

  // A tap on a floor (not a drag, and not on lettering or the panel) opens its plan.
  let down = null;
  canvas.addEventListener('pointerdown', (e) => { down = [e.clientX, e.clientY]; });
  canvas.addEventListener('click', (e) => {
    if (siteEditor?.active || e.target !== canvas || !down || Math.hypot(e.clientX - down[0], e.clientY - down[1]) > 5) return;
    const rect = canvas.getBoundingClientRect();
    const pointer = new THREE.Vector2(((e.clientX - rect.left) / rect.width) * 2 - 1, -((e.clientY - rect.top) / rect.height) * 2 + 1);
    const ray = new THREE.Raycaster();
    ray.setFromCamera(pointer, camera);
    const slabs = state.floors.filter((f, i) => f.slab && !state.hidden.has(i) && f.alpha > 0.5).map((f) => f.slab);
    const hit = ray.intersectObjects(slabs)[0];
    if (hit && hit.object.userData.floor !== state.focus) { closePanel(); planOf(hit.object.userData.floor); }
  });
}

function mainFloor() {
  const i = state.floors.findIndex((f) => f.floor.label === 'Main floor');
  return i >= 0 ? i : 0;
}

const project = (x, y, z) => {
  const v = new THREE.Vector3(x, y, z).project(camera);
  return [(v.x + 1) / 2 * canvas.clientWidth, (1 - v.y) / 2 * canvas.clientHeight, v.z];
};

/** Leader lines from each floor's name in the rail to that floor's outside corner, as a draftsman would key a drawing. */
function drawLeaders() {
  const show = state.focus === null && state.labels && state.intro >= 1;
  let paths = '';
  if (show) {
    for (const item of rail.querySelectorAll('[data-floor]')) {
      const f = state.floors[Number(item.dataset.floor)];
      if (state.hidden.has(Number(item.dataset.floor)) || f.alpha < 0.5) continue;
      const [ax, ay, az] = project(f.anchor[0], f.group.position.y, f.anchor[1]);
      if (az > 1) continue;
      const r = item.getBoundingClientRect();
      const sx = r.left - 8, sy = r.top + r.height / 2;
      const knee = sx - 36;
      paths += `<path d="M${sx} ${sy} H${knee} L${ax} ${ay}"/><circle cx="${ax}" cy="${ay}" r="3"/>`;
    }
  }
  leaders.innerHTML = paths;
}

/** The title block's north arrow turns with the view, so it always points to north on screen. */
function drawNorth() {
  const arrow = document.getElementById('north');
  if (!state.north) { arrow.hidden = true; return; }
  arrow.hidden = false;
  const [x0, y0] = project(0, 0, 0);
  const [x1, y1] = project(state.north[0], 0, state.north[1]);
  arrow.style.rotate = `${Math.atan2(x1 - x0, -(y1 - y0))}rad`;
}

// ---------- frame loop ----------

const ease = (t) => 1 - Math.pow(1 - Math.min(1, Math.max(0, t)), 3);
let last = performance.now();

let frames = 0;
function frame(now) {
  frames++;
  // Eases run on real time, so a slow frame moves further rather than the whole move taking longer.
  const dt = Math.min(0.5, (now - last) / 1000);
  last = now;

  // Intro: the pen draws each floor in turn, then the floors come together.
  if (state.intro < 1) state.intro = Math.min(1, state.intro + dt / 3.2);
  const goal = state.intro < 1 ? 1 : state.focus !== null ? 0 : state.expandTarget;
  state.expand += (goal - state.expand) * Math.min(1, dt * 3);

  state.floors.forEach((f, i) => {
    const count = f.lines.geometry.attributes.position.count;
    const local = ease((state.intro - i * 0.12) / 0.62);
    f.lines.geometry.setDrawRange(0, Math.floor(count * local));
    f.group.position.y = f.floor.elevation + state.expand * f.level * FLOOR_GAP;
    // In a floor's plan, the other floors go almost entirely away.
    // In a floor's plan the rest go almost entirely away; in the site's plan the house stays faintly in place.
    const siteFocused = state.floors[state.focus]?.site;
    const wanted = state.hidden.has(i) ? 0 : state.focus === null || state.focus === i ? 1 : siteFocused ? 0.22 : f.site ? 0 : 0.035;
    f.alpha += (wanted - f.alpha) * Math.min(1, dt * 6);
    f.group.visible = f.alpha > 0.01;
    for (const [k, m] of Object.entries(f.materials)) m.opacity = f.base[k] * f.alpha * (k === 'line' || k === 'outline' ? 1 : local);
    // Stacked floors would letter over each other, so room names wait until the floors are apart or one is chosen.
    const ready = state.labels && local > 0.95 && f.alpha > 0.6;
    // The site's lettering is sized for the whole lot, so it shows only in the site's own plan.
    const rooms = ready && (state.focus === i || (state.focus === null && state.expand > 0.4 && !f.site));
    for (const label of f.labels) label.setOpacity(rooms && (state.focus === i || !label.small) ? Math.min(1, f.alpha) : 0);
    f.dims.visible = state.labels && state.focus === i && f.alpha > 0.6;
    for (const tag of f.dims.userData.tags) tag.setOpacity(f.dims.visible ? 1 : 0);
  });
  if (panelMesh && ui.open && state.focus !== null) panelMesh.position.y = state.floors[state.focus].group.position.y + 0.05;

  if (state.tween) {
    const s = state.tween;
    const k = Math.min(1, dt * 3.2);
    const sph = new THREE.Spherical().setFromVector3(camera.position.clone().sub(controls.target));
    const dAz = s.azimuth === undefined ? 0 : Math.atan2(Math.sin(s.azimuth - sph.theta), Math.cos(s.azimuth - sph.theta));
    const dPolar = s.polar === undefined ? 0 : s.polar - sph.phi;
    sph.theta += dAz * k;
    sph.phi += dPolar * k;
    sph.radius += (s.radius - sph.radius) * k;
    if (s.fov !== undefined) { camera.fov += (s.fov - camera.fov) * k; camera.updateProjectionMatrix(); }
    controls.target.lerp(s.target, k);
    camera.position.copy(controls.target).add(new THREE.Vector3().setFromSpherical(sph));
    const fovDone = s.fov === undefined || Math.abs(s.fov - camera.fov) < 0.05;
    if (Math.abs(dAz) < 0.002 && Math.abs(dPolar) < 0.002 && Math.abs(s.radius - sph.radius) < 0.02 && fovDone) state.tween = null;
  }
  controls.autoRotate = state.spin;
  controls.autoRotateSpeed = 0.6;
  controls.update();
  const distance = camera.position.distanceTo(controls.target);
  scene.fog.near = distance * 0.75;
  scene.fog.far = distance * 2.4;
  renderer.render(scene, camera);
  if (drawn) drawn.updateHitTesting(); else overlay.render(scene, camera);
  drawLeaders();
  drawNorth();
  requestAnimationFrame(frame);
}

// ---------- the site editor ----------

let siteEditor = null;
let houseOrigin = [0, 0];
let sheetOpacity = 0;

/** Redraws the site from house.json's version of it, in place, keeping the view. */
function rebuildSite(raw) {
  let i = state.floors.findIndex((f) => f.site);
  const old = state.floors[i];
  if (old) {
    for (const label of old.labels) { if (label.surface) drawn.remove(label.surface); else label.element?.remove(); }
    scene.remove(old.group);
  } else {
    i = state.floors.length;
  }
  const next = buildSite(placeSite(raw, houseOrigin), i, { letter, onPlace: openRoom });
  next.alpha = old?.alpha ?? 1;
  state.floors[i] = next;
  scene.add(next.group);
  showSheet(sheetOpacity);
  if (!old) renderChrome();
}

/** Shows the traced-over plan image under the site at this opacity (0 hides it). */
function showSheet(opacity) {
  sheetOpacity = opacity;
  const underlay = state.floors.find((f) => f.site)?.underlay;
  if (!underlay) return;
  underlay.mesh.visible = opacity > 0;
  underlay.material.opacity = opacity;
}

async function saveSite(site) {
  const response = await fetch('/ha/site', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ site }) });
  if (!response.ok) throw new Error((await response.json().catch(() => ({}))).error ?? response.statusText);
}

// ---------- start ----------

async function start() {
  let read = readFromServer;
  try { await read('house.json'); } catch { read = await readFromDrop(); }
  const houseFile = await read('house.json');
  const house = await loadHouse(read);
  document.getElementById('title').textContent = house.name;
  document.getElementById('sheet-date').textContent = new Date().toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' }).toUpperCase();
  // Where live camera video can be watched (a hub's camera page, say), for cameras with no still picture.
  ui.cameraLink = houseFile.links?.cameras ?? null;
  const bearing = houseFile.north?.plusXBearingDegrees;
  if (Number.isFinite(bearing)) {
    // North is +X turned back by the bearing of +X; on the page, turning from +X towards +Z is clockwise.
    const a = (-bearing * Math.PI) / 180;
    state.north = [Math.cos(a), Math.sin(a)];
    document.getElementById('north-note').textContent = houseFile.north.note ?? '';
  }
  const hatch = hatchTexture();
  state.floors = house.floors.map((f, i) => buildFloor(f, i, hatch));
  // The site gets drawn even when there isn't one yet, so there's somewhere to draw it (except in the public demo).
  if (house.site || !DEMO) state.floors.push(buildSite(house.site ?? { features: [], places: [] }, state.floors.length, { letter, onPlace: openRoom }));
  state.floors.forEach((f) => scene.add(f.group));
  houseOrigin = house.origin;
  if (!DEMO) {
    const elevations = state.floors.filter((f) => !f.site).map((f) => f.floor.elevation);
    const garage = state.floors.find((f) => f.floor.label === 'Garage');
    siteEditor = new SiteEditor({
      scene, camera, canvas, controls, origin: house.origin, site: houseFile.site,
      levels: { back: Math.min(...elevations), front: garage?.floor.elevation ?? state.floors[mainFloor()].floor.elevation },
      onChange: rebuildSite, onSave: saveSite, onSheet: showSheet, areaNames: () => home.areas.map((a) => a.name),
    });
  }
  state.radius = Math.max(house.size[0], house.size[1]) * 2.1;
  scene.fog = new THREE.Fog(PAPER, 30, 90);
  resize();
  state.expandTarget = Number(params.get('expand') ?? 0.6);
  document.getElementById('expand').value = state.expandTarget;
  camera.position.setFromSpherical(new THREE.Spherical(state.radius * 1.15, VIEWS.axon.polar, VIEWS.axon.azimuth - 0.5));
  controls.target.copy(framing().target);
  overview('axon');
  if (params.get('intro') === '0') { state.intro = 1; state.expand = state.expandTarget; }
  if (params.has('focus')) planOf(Number(params.get('focus')));
  wireControls();
  renderChrome();
  home.start({ live: params.get('live') !== '0' }).catch(() => {});
  if (params.has('room')) {
    const [fi, name] = params.get('room').split(':');
    const room = state.floors[Number(fi)]?.floor.rooms.find((r) => r.name === name);
    if (room) setTimeout(() => openRoom(Number(fi), room), 300);
  }
  if (params.has('device')) setTimeout(() => { ui.device = params.get('device'); drawPanel(); }, 1200);
  if (params.has('selftest')) setTimeout(selfTest, Number(params.get('selftest')) || 4000);
  requestAnimationFrame(frame);
}

/** ?selftest: checks that Chrome's hit testing finds drawn lettering and panel buttons where they appear on screen. */
function selfTest() {
  const results = { drawn: DRAWN, connected: home.status.connected };
  // Chrome reports a drawn element's on-screen box through getBoundingClientRect; check its centre hit-tests to it.
  const hit = (surface, el) => {
    const box = el.getBoundingClientRect();
    const [x, y] = [box.left + box.width / 2, box.top + box.height / 2];
    const found = document.elementFromPoint(x, y);
    return { at: [Math.round(x), Math.round(y)], found: found?.closest('button, .room')?.textContent?.trim().slice(0, 30) ?? found?.tagName, ok: el.contains(found) || found === el };
  };
  if (DRAWN) {
    const f = state.floors[state.focus ?? mainFloor()];
    const label = f.labels.find((l) => l.surface?.matrix && l.element.classList.contains('room'));
    if (label) results.roomLabel = hit(label.surface, label.element);
    const button = panel.querySelector('[data-device]') ?? panel.querySelector('[data-area]');
    if (button && panelSurface?.matrix) results.panelButton = hit(panelSurface, button);
  }
  const sph = new THREE.Spherical().setFromVector3(camera.position.clone().sub(controls.target));
  results.frames = frames;
  results.camera = { phi: +sph.phi.toFixed(3), fov: +camera.fov.toFixed(1), tweening: Boolean(state.tween), focus: state.focus };
  results.panel = { open: ui.open, visible: panelMesh?.visible, size: panelSurface?.size, scale: panelMesh?.scale.toArray().map((v) => +v.toFixed(2)) };
  // Read the middle of a drawn label's texture back, to see whether the upload put any pixels there.
  const sample = (surface) => {
    if (!surface?.texture) return 'no texture';
    const gl = renderer.getContext();
    const fb = gl.createFramebuffer();
    gl.bindFramebuffer(gl.FRAMEBUFFER, fb);
    gl.framebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, renderer.properties.get(surface.texture).__webglTexture, 0);
    const [w, h] = surface.size.grid;
    const px = new Uint8Array(4 * w);
    gl.readPixels(0, Math.floor(h / 3), w, 1, gl.RGBA, gl.UNSIGNED_BYTE, px);
    gl.bindFramebuffer(gl.FRAMEBUFFER, null);
    gl.deleteFramebuffer(fb);
    renderer.resetState();
    let opaque = 0;
    for (let i = 3; i < px.length; i += 4) if (px[i] > 0) opaque++;
    return { grid: [w, h], opaqueInRow: opaque, status: gl.getError() };
  };
  const anyLabel = state.floors.flatMap((f) => f.labels).find((l) => l.surface?.texture);
  results.labelTexture = sample(anyLabel?.surface);
  results.panelTexture = sample(panelSurface);
  document.title = `SELFTEST ${JSON.stringify(results)}`;
}

start().catch((error) => {
  document.getElementById('drop').hidden = false;
  document.querySelector('#drop p').textContent = `Couldn't draw the house: ${error.message}`;
  console.error(error);
});
