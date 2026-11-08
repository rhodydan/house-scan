// A pretend Home Assistant with invented areas and devices, for building and testing the panel without a token.
// Run the dev server with HA_MOCK=1. Actions change the pretend states, so every control can be tried.
import { EventEmitter } from 'node:events';
import { applyService, demoCameraPicture, demoHome } from '../src/demo-devices.js';

export function mockHomeAssistant() {
  const { areas, devices, states, entities } = demoHome();
  const link = new EventEmitter();
  link.status = { connected: true, error: null };
  link.snapshot = () => ({ areas, devices, entities: entities.map((e) => ({ ...e, ...states.get(e.entity_id) })) });
  link.callService = async (id, service, data = {}) => {
    const next = applyService(states.get(id), service, data);
    if (!next) return;
    states.set(id, next);
    setTimeout(() => link.emit('state', next), 250); // a little delay, like a real device
  };
  link.camera = async () => ({ type: 'image/svg+xml', body: Buffer.from(demoCameraPicture()) });
  return link;
}
