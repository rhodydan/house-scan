// The assembled house as solid geometry, for export: walls with their openings cut, glass in the windows, a slab
// under each floor, and furniture as plain boxes. Metres, Y up, each floor at its height. Runs in Node or a browser.
import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';

const WALL_THICKNESS = 0.11;
const SLAB_THICKNESS = 0.1;

const point = (w, t) => [w.a[0] + w.along[0] * t, w.a[1] + w.along[1] * t];

/** A box from a to b on the floor plan, y0 to y1 high. */
function slabBox(a, b, y0, y1, thickness) {
  const dx = b[0] - a[0], dz = b[1] - a[1];
  const len = Math.hypot(dx, dz);
  if (len < 0.005 || y1 - y0 < 0.005) return null;
  const box = new THREE.BoxGeometry(len, y1 - y0, thickness);
  box.rotateY(Math.atan2(-dz, dx));
  box.translate((a[0] + b[0]) / 2, (y0 + y1) / 2, (a[1] + b[1]) / 2);
  return box;
}

function wallPieces(w) {
  const solid = [], glass = [];
  let start = 0;
  for (const g of w.gaps.filter((g) => g.to > g.from + 0.05)) {
    if (g.from > start + 0.01) solid.push(slabBox(point(w, start), point(w, g.from), w.bottom, w.top, WALL_THICKNESS));
    if (g.bottom > w.bottom + 0.03) solid.push(slabBox(point(w, g.from), point(w, g.to), w.bottom, g.bottom, WALL_THICKNESS));
    if (g.top < w.top - 0.03) solid.push(slabBox(point(w, g.from), point(w, g.to), Math.max(g.top, w.bottom), w.top, WALL_THICKNESS));
    if (g.kind === 'window') glass.push(slabBox(point(w, g.from), point(w, g.to), g.bottom, g.top, 0.012));
    start = Math.max(start, g.to);
  }
  if (w.length > start + 0.01) solid.push(slabBox(point(w, start), point(w, w.length), w.bottom, w.top, WALL_THICKNESS));
  return { solid: solid.filter(Boolean), glass: glass.filter(Boolean) };
}

const merged = (geometries) => {
  const list = geometries.filter(Boolean).map((g) => (g.index ? g.toNonIndexed() : g));
  return list.length ? mergeGeometries(list) : null;
};

export function buildSolidHouse(house) {
  const materials = {
    wall: new THREE.MeshStandardMaterial({ name: 'wall', color: 0xf2f2ee, roughness: 0.9 }),
    floor: new THREE.MeshStandardMaterial({ name: 'floor', color: 0xc8b89a, roughness: 0.8 }),
    glass: new THREE.MeshStandardMaterial({ name: 'glass', color: 0x9fc6e8, roughness: 0.1, transparent: true, opacity: 0.35 }),
    furniture: new THREE.MeshStandardMaterial({ name: 'furniture', color: 0x8a8f99, roughness: 0.9 }),
  };
  const root = new THREE.Group();
  root.name = house.name;
  for (const floor of house.floors) {
    const group = new THREE.Group();
    group.name = floor.label;
    group.position.y = floor.elevation;
    const pieces = floor.walls.map(wallPieces);
    const add = (name, geometry, material) => {
      if (!geometry) return;
      const mesh = new THREE.Mesh(geometry, material);
      mesh.name = `${floor.label} ${name}`;
      group.add(mesh);
    };
    add('walls', merged(pieces.flatMap((p) => p.solid)), materials.wall);
    add('windows', merged(pieces.flatMap((p) => p.glass)), materials.glass);
    if (floor.outline.length > 2) {
      const shape = new THREE.Shape(floor.outline.map(([x, z]) => new THREE.Vector2(x, z)));
      const slab = new THREE.ExtrudeGeometry(shape, { depth: SLAB_THICKNESS, bevelEnabled: false });
      slab.rotateX(Math.PI / 2);
      add('floor slab', slab, materials.floor);
    }
    const furniture = floor.objects.filter((o) => o.category !== 'stairs').map((o) => {
      const box = new THREE.BoxGeometry(o.width, o.height, o.depth);
      box.rotateY(Math.atan2(-o.along[1], o.along[0]));
      box.translate(o.center[0], o.bottom + o.height / 2, o.center[1]);
      return box;
    });
    add('furniture', merged(furniture), materials.furniture);
    root.add(group);
  }
  return root;
}
