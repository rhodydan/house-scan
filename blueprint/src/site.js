// The lot around the house: property line, walls, driveway, lawn, beds, paths, pool and outbuildings, drawn in the
// same white linework as the house, plus outdoor places (Backyard, Driveway, Front door...) that open their Home
// Assistant devices like rooms do. The shapes come from house.json's `site`, traced by hand from a site plan; nothing
// here is specific to one house.
//
// site: {
//   features: [{ kind, name?, points: [[x, z], ...], closed?, elevation?, height?, width? }
//              | { kind: 'pool', name?, center: [x, z], radius, elevation? }],
//   places: [{ name, at: [x, z], elevation? }],
// }
// kind: property, wall, driveway, lawn, bed, path, steps, patio, court, structure, pool. Metres, in the house's frame.
import * as THREE from 'three';

const geometryOf = (positions) => {
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3));
  return g;
};

/** A copy of a polyline moved sideways by `d` metres (positive to the left of its direction). */
function offset(points, d) {
  return points.map((p, i) => {
    const a = points[Math.max(0, i - 1)], b = points[Math.min(points.length - 1, i + 1)];
    const dx = b[0] - a[0], dz = b[1] - a[1], len = Math.hypot(dx, dz) || 1;
    return [p[0] - (dz / len) * d, p[1] + (dx / len) * d];
  });
}

const ringOf = (center, radius, n = 48) =>
  Array.from({ length: n }, (_, i) => [center[0] + radius * Math.cos((i / n) * 2 * Math.PI), center[1] + radius * Math.sin((i / n) * 2 * Math.PI)]);

function centroid(points) {
  const s = points.reduce((acc, p) => [acc[0] + p[0], acc[1] + p[1]], [0, 0]);
  return [s[0] / points.length, s[1] / points.length];
}

/** Line, dash and fill styling per kind of feature. */
const STYLE = {
  property: { dash: 'long', label: false },
  wall: { double: 0.15, label: false },
  driveway: { fill: 'hatch' },
  lawn: { fill: 'dots', dash: 'short' },
  bed: { fill: 'cross' },
  path: { double: 0.55, label: false },
  steps: { label: false },
  patio: { fill: 'cross' },
  court: { },
  structure: { box: true },
  pool: { fill: 'water', rings: 2 },
};

function patternTexture(kind) {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = 64;
  const g = canvas.getContext('2d');
  g.strokeStyle = g.fillStyle = 'rgba(255,255,255,0.9)';
  g.lineWidth = 2;
  if (kind === 'hatch' || kind === 'cross') {
    for (const o of [-64, 0, 64]) { g.beginPath(); g.moveTo(o, 64); g.lineTo(o + 64, 0); g.stroke(); }
    if (kind === 'cross') for (const o of [-64, 0, 64]) { g.beginPath(); g.moveTo(o, 0); g.lineTo(o + 64, 64); g.stroke(); }
  } else if (kind === 'dots') {
    for (const [x, y] of [[8, 10], [40, 22], [22, 44], [54, 54], [30, 4]]) { g.beginPath(); g.arc(x, y, 1.6, 0, 2 * Math.PI); g.fill(); }
  } else if (kind === 'water') {
    g.lineWidth = 1.5;
    for (const y of [16, 40]) { g.beginPath(); g.moveTo(0, y); g.bezierCurveTo(16, y - 6, 32, y + 6, 64, y); g.stroke(); }
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.wrapS = texture.wrapT = THREE.RepeatWrapping;
  texture.repeat.set(1.2, 1.2);
  return texture;
}

/**
 * Builds the site as a floor-shaped object for main.js: a group, its linework (for the draw-in), materials to fade,
 * lettering, bounds for framing, and a ground slab to tap. `letter` makes lettering; `onPlace` opens a place's panel.
 */
export function buildSite(site, index, { letter, onPlace }) {
  const group = new THREE.Group();
  group.name = 'Site';
  const lines = [], dashedLong = [], dashedShort = [];
  const fills = {};
  const labels = [];
  const push = (list, pts, y, closed) => {
    for (let i = 0; i < pts.length - (closed ? 0 : 1); i++) {
      const p = pts[i], q = pts[(i + 1) % pts.length];
      list.push(p[0], y, p[1], q[0], y, q[1]);
    }
  };
  const all = [];

  for (const f of site.features ?? []) {
    const style = STYLE[f.kind] ?? {};
    const y = (f.elevation ?? 0) + 0.02;
    const pts = f.kind === 'pool' ? ringOf(f.center, f.radius) : f.points;
    const closed = f.kind === 'pool' || (f.closed ?? ['driveway', 'lawn', 'bed', 'patio', 'court', 'structure'].includes(f.kind));
    all.push(...pts);
    const target = style.dash === 'long' ? dashedLong : style.dash === 'short' ? dashedShort : lines;
    if (style.double) {
      push(lines, offset(pts, style.double), y, closed);
      push(lines, offset(pts, -style.double), y, closed);
    } else {
      push(target, pts, y, closed);
    }
    if (style.rings) push(lines, ringOf(f.center, f.radius * 0.9), y, true);
    if (f.kind === 'steps') for (const d of [0.4, 0.8]) push(lines, offset(pts, d), y - d * 0.3, false);
    if (style.box) {
      const h = f.height ?? 2.5;
      push(lines, pts, y + h, true);
      for (const p of pts) lines.push(p[0], y, p[1], p[0], y + h, p[1]);
      if (f.roof === 'pyramid') { const c = centroid(pts); for (const p of pts) lines.push(p[0], y + h, p[1], c[0], y + h + 1.2, c[1]); }
    }
    if (f.kind === 'court' && pts.length === 4) {
      const mid = (a, b) => [(a[0] + b[0]) / 2, (a[1] + b[1]) / 2];
      const [a, b, c, d] = pts;
      lines.push(...[mid(a, b), mid(c, d)].flatMap((p) => [p[0], y, p[1]]));
    }
    if (style.fill && closed) {
      const shape = new THREE.Shape(pts.map(([x, z]) => new THREE.Vector2(x, z)));
      const geometry = new THREE.ShapeGeometry(shape);
      geometry.rotateX(Math.PI / 2);
      geometry.translate(0, y - 0.01, 0);
      (fills[style.fill] ??= []).push(geometry);
    }
    if (f.name && style.label !== false) {
      const at = f.kind === 'pool' ? f.center : centroid(pts);
      const label = letter(group, `<span>${f.name}</span>`, 'note site-note', [at[0], y + (style.box ? (f.height ?? 2.5) + 0.05 : 0.03), at[1]], { size: 2.6 });
      labels.push(label);
    }
  }

  const materials = {
    line: new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.8 }),
    dashedLong: new THREE.LineDashedMaterial({ color: 0xffffff, transparent: true, opacity: 0.7, dashSize: 1.2, gapSize: 0.35 }),
    dashedShort: new THREE.LineDashedMaterial({ color: 0xffffff, transparent: true, opacity: 0.45, dashSize: 0.25, gapSize: 0.2 }),
  };
  const lineMesh = new THREE.LineSegments(geometryOf(lines), materials.line);
  group.add(lineMesh);
  for (const [list, material] of [[dashedLong, materials.dashedLong], [dashedShort, materials.dashedShort]]) {
    const m = new THREE.LineSegments(geometryOf(list), material);
    m.computeLineDistances();
    group.add(m);
  }
  for (const [kind, geometries] of Object.entries(fills)) {
    const texture = patternTexture(kind);
    const material = new THREE.MeshBasicMaterial({ map: texture, transparent: true, opacity: kind === 'water' ? 0.35 : 0.14, side: THREE.DoubleSide, depthWrite: false });
    materials[`fill-${kind}`] = material;
    for (const g of geometries) group.add(new THREE.Mesh(g, material));
  }

  // Outdoor places: tap one for its Home Assistant devices, like a room.
  for (const place of site.places ?? []) {
    const y = (place.elevation ?? 0) + 0.06;
    const room = { name: place.name, center: place.at, area: null };
    const label = letter(group, `<i></i><b>${place.name}</b>`, 'room place', [place.at[0], y, place.at[1]], { size: 3.2, onClick: () => onPlace(index, room) });
    labels.push(label);
    all.push(place.at);
  }

  // The lot as a tappable slab: its property line if there is one, else everything drawn.
  const lot = (site.features ?? []).find((f) => f.kind === 'property' && f.closed !== false)?.points;
  let slab = null;
  if (lot && lot.length > 2) {
    const geometry = new THREE.ShapeGeometry(new THREE.Shape(lot.map(([x, z]) => new THREE.Vector2(x, z))));
    geometry.rotateX(Math.PI / 2);
    slab = new THREE.Mesh(geometry, new THREE.MeshBasicMaterial({ transparent: true, opacity: 0, depthWrite: false, side: THREE.DoubleSide }));
    slab.userData.floor = index;
    group.add(slab);
  }

  const bounds = {
    min: [Math.min(...all.map((p) => p[0])), Math.min(...all.map((p) => p[1]))],
    max: [Math.max(...all.map((p) => p[0])), Math.max(...all.map((p) => p[1]))],
  };
  const base = Object.fromEntries(Object.entries(materials).map(([k, m]) => [k, m.opacity]));
  const dims = new THREE.Group();
  dims.userData.tags = [];
  const anchor = all.reduce((best, p) => (p[0] > best[0] ? p : best), all[0] ?? [0, 0]);
  return {
    group, lines: lineMesh, materials, base, labels, dims, slab, anchor, bounds, level: 0, alpha: 1, site: true,
    floor: { label: 'Site', elevation: -0.01, rooms: (site.places ?? []).map((p) => ({ name: p.name, center: p.at, area: null })), outline: lot ?? [] },
  };
}
