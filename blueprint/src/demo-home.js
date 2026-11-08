// The public demo's Home Assistant: the same pretend home as the dev server's mock mode, run in the browser, so the
// demo needs no server and no real home. Same interface as Home.
import { Home } from './ha.js';
import { applyService, demoCameraPicture, demoHome } from './demo-devices.js';

export class DemoHome extends Home {
  async start() {
    const { areas, devices, states, entities } = demoHome();
    this.states = states;
    this.areas = areas;
    this.devices = devices;
    this.entities = new Map(entities.map((e) => [e.entity_id, { ...e, ...states.get(e.entity_id) }]));
    this.status = { connected: true, error: null, demo: true };
    this.changed();
  }

  async chooseArea(floor, room, areaId) {
    this.rooms = { ...this.rooms, [`${floor}/${room}`]: areaId || undefined };
    this.changed();
  }

  async call(entityId, service, data = {}) {
    const next = applyService(this.states.get(entityId), service, data);
    if (!next) return;
    this.states.set(entityId, next);
    // A short delay, like a real device answering.
    setTimeout(() => { this.entities.set(entityId, { ...this.entities.get(entityId), ...next }); this.changed(entityId); }, 250);
  }

  cameraUrl() {
    return `data:image/svg+xml;charset=utf-8,${encodeURIComponent(demoCameraPicture())}`;
  }
}
