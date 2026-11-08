// Turns House Scan floor exports plus a house file (floor poses, heights, hand corrections) into one model in a
// shared frame: metres, Y up, X and Z horizontal, seen from above with X right and Z down the page.

const finite = (...values) => values.every((v) => typeof v === 'number' && Number.isFinite(v));

/** Turns a point about the origin; a positive angle turns +X towards +Z (the convention the poses were fitted in). */
export function turn([x, z], degrees) {
  const a = (degrees * Math.PI) / 180;
  return [x * Math.cos(a) - z * Math.sin(a), x * Math.sin(a) + z * Math.cos(a)];
}

const sub = (a, b) => [a[0] - b[0], a[1] - b[1]];
const add = (a, b) => [a[0] + b[0], a[1] + b[1]];
const scale = (a, s) => [a[0] * s, a[1] * s];
const dot = (a, b) => a[0] * b[0] + a[1] * b[1];
const length = (a) => Math.hypot(a[0], a[1]);
const unit = (a) => scale(a, 1 / (length(a) || 1));

/** A surface's two ends and direction, in its scan's frame. */
function segmentOf(surface) {
  const t = surface.transform;
  const along = unit([t[0], t[2]]);
  const center = [surface.position.x, surface.position.z];
  const half = surface.size.width / 2;
  return { a: sub(center, scale(along, half)), b: add(center, scale(along, half)), along, center };
}

function usable(surface) {
  return surface.transform?.every((v) => finite(v)) && finite(surface.size.width, surface.size.height, surface.position.y);
}

/** Distance from a point to a segment, and how far along it (0 at a, the segment length at b) the point falls. */
function project(point, a, b) {
  const d = sub(b, a);
  const len = length(d) || 1;
  const t = dot(sub(point, a), d) / len;
  const clamped = Math.max(0, Math.min(len, t));
  const foot = add(a, scale(d, clamped / len));
  return { distance: length(sub(point, foot)), t, len };
}

function applyCorrections(doc, fix) {
  if (!fix) return { walls: doc.walls, doors: doc.doors, callouts: [] };
  const removed = new Set(fix.removeWalls ?? []);
  const nearestWall = (surface) => {
    const c = segmentOf(surface).center;
    let best = null;
    for (const w of doc.walls) {
      const s = segmentOf(w);
      const d = project(c, s.a, s.b).distance;
      if (!best || d < best.d) best = { d, w };
    }
    return best?.w;
  };

  let doors = doc.doors.map((door) => ({ ...door }));
  if (fix.moveDoorsOntoWall) {
    const [p, q] = fix.moveDoorsOntoWall.line;
    const along = unit(sub(q, p));
    doors = doors.map((door) => {
      if (nearestWall(door)?.id !== fix.moveDoorsOntoWall.from) return door;
      const c = segmentOf(door).center;
      const foot = add(p, scale(along, dot(sub(c, p), along)));
      const t = [...door.transform];
      [t[0], t[2], t[12], t[14]] = [along[0], along[1], foot[0], foot[1]];
      return { ...door, transform: t, position: { ...door.position, x: foot[0], z: foot[1] } };
    });
  }

  const callouts = (fix.callouts ?? []).map((callout) => {
    const ids = new Set(callout.nearDoorsOnWall);
    const near = doc.doors.filter((d) => d.size.width < 1.2 && ids.has(nearestWall(d)?.id)).map((d) => segmentOf(d).center);
    if (!near.length) return null;
    const middle = scale(near.reduce(add, [0, 0]), 1 / near.length);
    const room = doc.rooms[0] ? [doc.rooms[0].center.x, doc.rooms[0].center.z] : middle;
    return { text: callout.text, at: add(middle, scale(unit(sub(room, middle)), 1.0)) };
  }).filter(Boolean);

  const floorY = doc.floors[0].position.y;
  const walls = doc.walls.filter((w) => !removed.has(w.id));
  for (const [i, w] of (fix.addWalls ?? []).entries()) {
    const along = unit(sub(w.to, w.from));
    const mid = scale(add(w.from, w.to), 0.5);
    walls.push({
      id: `added-wall-${i}`, size: { width: length(sub(w.to, w.from)), height: w.height, depth: 0 },
      position: { x: mid[0], y: floorY + w.height / 2, z: mid[1] },
      transform: [along[0], 0, along[1], 0, 0, 1, 0, 0, -along[1], 0, along[0], 0, mid[0], floorY + w.height / 2, mid[1], 1],
      added: true,
    });
  }
  for (const [i, d] of (fix.addDoors ?? []).entries()) {
    doors.push({
      id: `added-door-${i}`, size: { width: d.width, height: d.height, depth: 0 },
      position: { x: d.center[0], y: floorY + d.height / 2, z: d.center[1] },
      transform: [d.along[0], 0, d.along[1], 0, 0, 1, 0, 0, -d.along[1], 0, d.along[0], 0, d.center[0], floorY + d.height / 2, d.center[1], 1],
      added: true, label: d.label,
    });
  }
  return { walls, doors, callouts };
}

/** Each wall split into runs of solid wall, with its doors, windows and openings cut out. */
function cutWalls(walls, gaps, floorY) {
  const out = walls.map((w) => {
    const s = segmentOf(w);
    const bottom = w.position.y - w.size.height / 2 - floorY;
    return { ...s, bottom, top: bottom + w.size.height, length: w.size.width, gaps: [], added: !!w.added };
  });
  for (const gap of gaps) {
    const g = segmentOf(gap.surface);
    let best = null;
    for (const w of out) {
      if (Math.abs(dot(g.along, w.along)) < Math.cos((12 * Math.PI) / 180)) continue;
      const p = project(g.center, w.a, w.b);
      if (p.distance < 0.4 && p.t > -0.2 && p.t < p.len + 0.2 && (!best || p.distance < best.p.distance)) best = { w, p };
    }
    const bottom = gap.surface.position.y - gap.surface.size.height / 2 - floorY;
    const cut = {
      kind: gap.kind, label: gap.surface.label,
      from: Math.max(0, best ? best.p.t - gap.surface.size.width / 2 : 0),
      to: best ? Math.min(best.w.length, best.p.t + gap.surface.size.width / 2) : 0,
      bottom: gap.kind === 'door' || gap.kind === 'opening' ? Math.max(bottom, 0) : bottom,
      top: bottom + gap.surface.size.height,
    };
    if (best) best.w.gaps.push(cut);
  }
  for (const w of out) w.gaps.sort((p, q) => p.from - q.from);
  return out;
}

/** Loads one house: the house file plus each floor's export. `read(name)` returns a file's parsed JSON. */
export async function loadHouse(read) {
  const house = await read('house.json');
  const floors = [];
  for (const spec of house.floors) {
    const doc = await read(spec.file);
    const fixed = applyCorrections(doc, house.corrections?.[spec.file]);
    const floorY = spec.floorY ?? doc.floors[0].position.y;
    const place = (p) => add(turn(p, spec.angleDegrees), spec.offset);
    const gaps = [
      ...fixed.doors.filter(usable).map((surface) => ({ surface, kind: 'door' })),
      ...doc.windows.filter(usable).map((surface) => ({ surface, kind: 'window' })),
      ...doc.openings.filter(usable).map((surface) => ({ surface, kind: 'opening' })),
    ];
    const walls = cutWalls(fixed.walls.filter(usable), gaps, floorY).map((w) => ({ ...w, a: place(w.a), b: place(w.b), along: unit(sub(place(w.b), place(w.a))) }));

    const slab = doc.floors[0];
    const t = slab.transform;
    const outline = finite(...t) ? slab.polygonCorners.filter((p) => finite(p.x, p.y, p.z))
      .map((p) => place([t[0] * p.x + t[4] * p.y + t[8] * p.z + t[12], t[2] * p.x + t[6] * p.y + t[10] * p.z + t[14]])) : [];

    const objects = doc.objects.filter((o) => finite(...o.transform, o.size.width, o.size.depth, o.size.height)).map((o) => {
      const o2 = o.transform;
      const along = turn(unit([o2[0], o2[2]]), spec.angleDegrees);
      const across = turn(unit([o2[8], o2[10]]), spec.angleDegrees);
      const center = place([o.position.x, o.position.z]);
      const bottom = o.position.y - o.size.height / 2 - floorY;
      return { category: o.category, center, along, across, width: o.size.width, depth: o.size.depth, bottom, height: o.size.height };
    });

    const rooms = doc.rooms.filter((r) => finite(r.center.x, r.center.z)).map((r) => ({
      name: doc.mergeStatus === 'singleRoom' && /^Room \d+$/.test(r.name) ? spec.label : r.name,
      center: place([r.center.x, r.center.z]), area: finite(r.floorAreaSquareMetres) ? r.floorAreaSquareMetres : null,
    }));

    floors.push({
      label: spec.label, elevation: spec.elevation, walls, outline, objects, rooms,
      callouts: fixed.callouts.map((c) => ({ text: c.text, at: place(c.at) })),
    });
  }

  // Centre the house on the origin.
  const points = floors.flatMap((f) => f.walls.flatMap((w) => [w.a, w.b]));
  const min = [Math.min(...points.map((p) => p[0])), Math.min(...points.map((p) => p[1]))];
  const max = [Math.max(...points.map((p) => p[0])), Math.max(...points.map((p) => p[1]))];
  const mid = scale(add(min, max), 0.5);
  const shift = (p) => sub(p, mid);
  for (const f of floors) {
    f.walls = f.walls.map((w) => ({ ...w, a: shift(w.a), b: shift(w.b) }));
    f.outline = f.outline.map(shift);
    f.objects = f.objects.map((o) => ({ ...o, center: shift(o.center) }));
    f.rooms = f.rooms.map((r) => ({ ...r, center: shift(r.center) }));
    f.callouts = f.callouts.map((c) => ({ ...c, at: shift(c.at) }));
  }
  return { name: house.name, floors, size: sub(max, min), origin: mid, site: house.site ? placeSite(house.site, mid) : null };
}

/**
 * The site as drawn: house.json keeps it in the stacked floors' frame, and the drawing is centred on the house, so
 * everything moves by `origin`. A traced-over plan image (`underlay`) gets its four corners worked out from its fit:
 * which pixel sits at which point, how many pixels to a metre, and the compass bearing of the house's +X on it
 * (north up the image).
 */
export function placeSite(site, origin) {
  const shift = (p) => sub(p, origin);
  const placed = {
    features: (site.features ?? []).map((f) => ({ ...f, ...(f.points ? { points: f.points.map(shift) } : {}), ...(f.center ? { center: shift(f.center) } : {}) })),
    places: (site.places ?? []).map((p) => ({ ...p, at: shift(p.at) })),
  };
  const u = site.underlay;
  if (u?.file && finite(u.width, u.height, u.bearing, u.pxPerMetre)) {
    const b = (u.bearing * Math.PI) / 180;
    const toPlan = ([px, py]) => {
      const d = [(px - u.anchorPx[0]) / u.pxPerMetre, (py - u.anchorPx[1]) / u.pxPerMetre];
      return shift([u.anchorAt[0] + d[0] * Math.sin(b) - d[1] * Math.cos(b), u.anchorAt[1] + d[0] * Math.cos(b) + d[1] * Math.sin(b)]);
    };
    placed.underlay = { file: u.file, elevation: u.elevation ?? 0, corners: [[0, 0], [u.width, 0], [u.width, u.height], [0, u.height]].map(toPlan) };
  }
  return placed;
}

/** 3.05 → 10'-0", the way a draftsman writes it. */
export function feetInches(metres) {
  if (!finite(metres)) return '?';
  const inches = Math.round(metres / 0.0254);
  return `${Math.floor(inches / 12)}'-${inches % 12}"`;
}

export const squareFeet = (m2) => `${Math.round(m2 * 10.7639)} SQ FT`;
