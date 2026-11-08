// The page's view of Home Assistant, through the dev server's bridge (server/ha-bridge.js). No token here.

const norm = (s) => String(s ?? '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

export class Home extends EventTarget {
  status = { connected: false, error: 'starting' };
  areas = [];
  devices = [];
  entities = new Map();
  rooms = {};

  /** `live: false` loads states once without the change stream (headless screenshots wait forever on an open stream). */
  async start({ live = true } = {}) {
    this.rooms = await (await fetch('/ha/rooms')).json().catch(() => ({}));
    this.status = await (await fetch('/ha/status')).json();
    if (this.status.connected) await this.load();
    this.changed();
    if (!this.status.connected) { setTimeout(() => this.start({ live }), 15000); return; }
    if (!live) return;
    const events = new EventSource('/ha/events');
    events.onmessage = (e) => {
      const state = JSON.parse(e.data);
      const known = this.entities.get(state.entity_id);
      if (known) this.entities.set(state.entity_id, { ...known, ...state });
      this.changed(state.entity_id);
    };
    events.addEventListener('status', async (e) => {
      this.status = JSON.parse(e.data);
      if (this.status.connected) await this.load();
      this.changed();
    });
  }

  async load() {
    const snapshot = await (await fetch('/ha/snapshot')).json();
    this.areas = snapshot.areas ?? [];
    this.devices = snapshot.devices ?? [];
    this.entities = new Map((snapshot.entities ?? []).map((e) => [e.entity_id, e]));
  }

  changed(entityId = null) {
    this.dispatchEvent(new CustomEvent('change', { detail: entityId }));
  }

  /** The Home Assistant area for a scanned room: the user's choice if they made one, or an exact, unambiguous name match. */
  areaFor(floor, room, sameNameCount = 1) {
    const chosen = this.rooms[`${floor}/${room}`];
    if (chosen) return { area: this.areas.find((a) => a.area_id === chosen) ?? null, chosen: true };
    if (sameNameCount > 1) return { area: null, chosen: false };
    const matches = this.areas.filter((a) => norm(a.name) === norm(room));
    return { area: matches.length === 1 ? matches[0] : null, chosen: false };
  }

  async chooseArea(floor, room, areaId) {
    const response = await fetch('/ha/rooms', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ key: `${floor}/${room}`, area_id: areaId }) });
    this.rooms = await response.json();
    this.changed();
  }

  /** The area's devices, each with its entities, most useful first. Entities with no device stand alone. */
  devicesIn(areaId) {
    const entities = [...this.entities.values()].filter((e) => e.area_id === areaId);
    const groups = new Map();
    for (const e of entities) {
      const key = e.device_id ?? e.entity_id;
      if (!groups.has(key)) {
        const device = this.devices.find((d) => d.id === e.device_id);
        groups.set(key, { id: key, name: device?.name ?? e.name, entities: [] });
      }
      groups.get(key).entities.push(e);
    }
    const rank = (e) => PRIMARY.indexOf(e.entity_id.split('.')[0]) >>> 0;
    for (const g of groups.values()) g.entities.sort((a, b) => rank(a) - rank(b));
    return [...groups.values()].sort((a, b) => rank(a.entities[0]) - rank(b.entities[0]) || a.name.localeCompare(b.name));
  }

  cameraUrl(entityId, tick = 0) {
    return `/ha/camera/${encodeURIComponent(entityId)}?t=${tick}`;
  }

  async call(entityId, service, data = {}) {
    const response = await fetch('/ha/service', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ entity_id: entityId, service, data }) });
    if (!response.ok) throw new Error((await response.json()).error ?? response.statusText);
  }
}

export const PRIMARY = ['lock', 'climate', 'light', 'cover', 'fan', 'switch', 'media_player', 'vacuum', 'camera', 'scene', 'button', 'input_boolean', 'binary_sensor', 'sensor'];
