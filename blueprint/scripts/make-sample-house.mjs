// Writes an invented two-storey house in House Scan's export format (house-scan-floor/1), plus a house.json that stacks
// it, into blueprint/demo/. It's the house the public demo and the screenshots use, so no real home appears anywhere.
// Usage: node scripts/make-sample-house.mjs
import { createHash } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';

const OUT = path.resolve(import.meta.dirname, '..', 'demo');
const WALL_HEIGHT = 2.7;

/** Stable UUIDs, so regenerating the house doesn't change every id. */
const uuid = (seed) => {
  const h = createHash('sha1').update(seed).digest('hex');
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-5${h.slice(13, 16)}-a${h.slice(17, 20)}-${h.slice(20, 32)}`.toUpperCase();
};

/** A RoomPlan-style transform: X along the surface, Y up, Z its normal, column by column. */
function transform([ux, uz], [cx, cy, cz]) {
  return [ux, 0, uz, 0, 0, 1, 0, 0, -uz, 0, ux, 0, cx, cy, cz, 1];
}
function rotation([ux, uz]) {
  const yaw = Math.atan2(-uz, ux);
  return { yawDegrees: +(yaw * 180 / Math.PI).toFixed(2), quaternion: { x: 0, y: +Math.sin(yaw / 2).toFixed(5), z: 0, w: +Math.cos(yaw / 2).toFixed(5) } };
}

function surface(kind, seed, a, b, { bottom = 0, height = WALL_HEIGHT, at = null, width = null } = {}) {
  const len = Math.hypot(b[0] - a[0], b[1] - a[1]);
  const u = [(b[0] - a[0]) / len, (b[1] - a[1]) / len];
  const t = at ?? len / 2;
  const w = width ?? len;
  const c = [a[0] + u[0] * t, bottom + height / 2, a[1] + u[1] * t];
  return {
    id: uuid(`${kind}:${seed}`), kind, size: { width: w, height, depth: 0 },
    position: { x: c[0], y: c[1], z: c[2] }, rotation: rotation(u), transform: transform(u, c),
    confidence: 'high', story: 0, completedEdges: [], polygonCorners: [],
    ...(kind === 'door' ? { isOpen: false } : {}),
  };
}

function object(seed, category, [x, z], width, depth, height, along = [1, 0]) {
  return {
    id: uuid(`object:${seed}`), category, attributes: [], size: { width, height, depth },
    position: { x, y: height / 2, z }, rotation: rotation(along), transform: transform(along, [x, height / 2, z]),
    confidence: 'high', story: 0,
  };
}

function floor({ name, walls, doors, windows, openings, objects, rooms }) {
  const corners = [[0, 0], [11, 0], [11, 8], [0, 8]];
  const W = walls.map(([a, b], i) => surface('wall', `${name}:${i}`, a, b));
  const onWall = (kind, list, opts) => list.map(([i, at, width, extra = {}], n) => {
    const [a, b] = walls[i];
    return surface(kind, `${name}:${kind}:${n}`, a, b, { at, width, ...opts, ...extra });
  });
  return {
    format: 'house-scan-floor/1',
    units: 'metres, degrees',
    coordinateSystem: 'Y up, X and Z horizontal, right-handed; origin and orientation are arbitrary, set by where the scan began',
    project: 'Sample House',
    floor: name,
    exportedAt: '2026-01-01T00:00:00Z',
    mergeStatus: 'merged',
    rooms: rooms.map(([roomName, x0, z0, x1, z1]) => ({
      name: roomName, center: { x: (x0 + x1) / 2, y: 0, z: (z0 + z1) / 2 }, floorAreaSquareMetres: +((x1 - x0) * (z1 - z0)).toFixed(2),
    })),
    unmergedRooms: [],
    warnings: [],
    walls: W,
    doors: onWall('door', doors, { height: 2.03 }),
    windows: onWall('window', windows, { bottom: 0.9, height: 1.3 }),
    openings: onWall('opening', openings, { height: 2.2 }),
    floors: [{
      id: uuid(`floor:${name}`), kind: 'floor', size: { width: 11, height: 8, depth: 0 }, position: { x: 0, y: 0, z: 0 },
      rotation: rotation([1, 0]), transform: [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1], confidence: 'high', story: 0,
      completedEdges: [], polygonCorners: corners.map(([x, z]) => ({ x, y: 0, z })),
    }],
    objects,
    sections: [],
  };
}

// The outside walls, then the inside walls. Plan coordinates in metres: X to the right, Z down the page.
const outside = [[[0, 0], [11, 0]], [[11, 0], [11, 8]], [[11, 8], [0, 8]], [[0, 8], [0, 0]]];

const main = floor({
  name: 'Main floor',
  walls: [...outside, [[5, 0], [5, 8]], [[7, 0], [7, 8]], [[0, 4], [5, 4]], [[7, 4.5], [11, 4.5]], [[5, 1.6], [7, 1.6]]],
  // [wall, distance along it, width]
  doors: [[2, 5, 1.0], [4, 6, 0.9], [4, 2.6, 0.9], [5, 2.6, 0.9], [5, 6.2, 0.9], [8, 1, 0.8], [0, 2.2, 0.9]],
  windows: [[2, 8.5, 2.0], [3, 2, 1.5], [2, 2, 1.6], [1, 6.2, 1.4], [0, 3.6, 1.2], [3, 6, 1.2], [0, 9, 1.6], [1, 2.2, 1.4]],
  openings: [[6, 3, 1.6]],
  objects: [
    object('sofa', 'sofa', [2.5, 7.2], 2.2, 0.9, 0.85), object('coffee', 'table', [2.5, 6.1], 1.1, 0.6, 0.45),
    object('tv', 'television', [0.25, 6], 1.4, 0.1, 0.8, [0, 1]), object('fridge', 'refrigerator', [0.45, 0.45], 0.9, 0.75, 1.8),
    object('stove', 'stove', [2.2, 0.35], 0.76, 0.65, 0.92), object('sink', 'sink', [3.6, 0.35], 0.9, 0.6, 0.92),
    object('island', 'storage', [2.6, 2.3], 2.0, 0.9, 0.92), object('dining', 'table', [9, 2.2], 1.8, 1.0, 0.75),
    object('desk', 'table', [9.5, 7.3], 1.5, 0.7, 0.75), object('chair', 'chair', [9.5, 6.6], 0.6, 0.6, 0.9),
    object('stairs', 'stairs', [6, 4.2], 1.0, 3.2, 2.7), object('toilet', 'toilet', [6.4, 0.4], 0.4, 0.7, 0.75),
  ],
  rooms: [['Living Room', 0, 4, 5, 8], ['Kitchen', 0, 0, 5, 4], ['Dining Room', 7, 0, 11, 4.5], ['Office', 7, 4.5, 11, 8], ['Hallway', 5, 1.6, 7, 8], ['Powder Room', 5, 0, 7, 1.6]],
});

const upper = floor({
  name: 'Upper floor',
  walls: [...outside, [[5, 0], [5, 8]], [[7, 0], [7, 8]], [[0, 4.5], [5, 4.5]], [[7, 3], [11, 3]], [[5, 1.6], [7, 1.6]]],
  doors: [[4, 2.5, 0.9], [4, 6.2, 0.9], [5, 2.3, 0.8], [5, 5.5, 0.9], [8, 1, 0.8]],
  windows: [[0, 2.5, 1.6], [3, 2.2, 1.2], [2, 8.5, 1.6], [3, 6, 1.2], [0, 9, 1.0], [2, 2, 1.6], [1, 5.5, 1.4]],
  openings: [],
  objects: [
    object('bed1', 'bed', [2.5, 1.6], 1.9, 2.1, 0.6), object('bed2', 'bed', [2, 6.6], 1.4, 2.0, 0.6),
    object('bed3', 'bed', [9.4, 6.4], 1.4, 2.0, 0.6), object('tub', 'bathtub', [9.3, 0.45], 1.6, 0.75, 0.55),
    object('vanity', 'sink', [7.5, 2.6], 0.9, 0.55, 0.85), object('toilet2', 'toilet', [10.6, 2.3], 0.4, 0.7, 0.75, [0, 1]),
    object('washer', 'washer/dryer', [6, 0.4], 1.4, 0.65, 0.9), object('dresser', 'storage', [4.4, 3.9], 1.2, 0.5, 0.9, [0, 1]),
  ],
  rooms: [['Primary Bedroom', 0, 0, 5, 4.5], ['Bedroom 2', 0, 4.5, 5, 8], ['Bathroom', 7, 0, 11, 3], ['Bedroom 3', 7, 3, 11, 8], ['Upstairs Hall', 5, 1.6, 7, 8], ['Laundry', 5, 0, 7, 1.6]],
});

await mkdir(OUT, { recursive: true });
await writeFile(path.join(OUT, 'Sample-House-Main-floor.json'), JSON.stringify(main, null, 1));
await writeFile(path.join(OUT, 'Sample-House-Upper-floor.json'), JSON.stringify(upper, null, 1));
await writeFile(path.join(OUT, 'house.json'), JSON.stringify({
  format: 'house-blueprint/1',
  name: 'Sample House',
  north: { plusXBearingDegrees: 90, note: 'Invented house' },
  floors: [
    { file: 'Sample-House-Main-floor.json', label: 'Main floor', angleDegrees: 0, offset: [0, 0], elevation: 0, floorY: 0 },
    { file: 'Sample-House-Upper-floor.json', label: 'Upper floor', angleDegrees: 0, offset: [0, 0], elevation: 3.0, floorY: 0 },
  ],
  corrections: {},
}, null, 1));
console.log(`Wrote the sample house to ${OUT}`);
