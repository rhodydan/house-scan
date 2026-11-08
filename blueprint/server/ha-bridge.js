// A Vite plugin that sits between the page and Home Assistant. The Home Assistant token stays here, read from a file
// only its owner can read; the page gets areas, devices and states, a stream of changes, and a short list of actions.
//
//   GET  /ha/status            connected or not, and why
//   GET  /ha/snapshot          areas, devices, entities (with state)
//   GET  /ha/events            server-sent events: one per state change
//   POST /ha/service           { entity_id, service, data } for an allowed domain and service
//   GET  /ha/camera/<entity>   a camera's current picture
//   GET  /ha/rooms             which Home Assistant area each scanned room is
//   POST /ha/rooms             { key, area_id } to set one
import { EventEmitter } from 'node:events';
import { readFile, writeFile } from 'node:fs/promises';
import { homedir } from 'node:os';
import path from 'node:path';
import { mockHomeAssistant } from './ha-mock.js';

export const TOKEN_FILE = path.join(homedir(), '.config', 'house-blueprint', 'ha-token');
/** Home Assistant's address: HA_URL, else this file, else Home Assistant's usual local name. */
export const URL_FILE = path.join(homedir(), '.config', 'house-blueprint', 'ha-url');

/** What the page may do, by domain. Anything else is refused. */
export const SERVICES = {
  light: ['turn_on', 'turn_off', 'toggle'],
  switch: ['turn_on', 'turn_off', 'toggle'],
  input_boolean: ['turn_on', 'turn_off', 'toggle'],
  fan: ['turn_on', 'turn_off', 'toggle', 'set_percentage'],
  lock: ['lock', 'unlock'],
  climate: ['set_temperature', 'set_hvac_mode'],
  cover: ['open_cover', 'close_cover', 'stop_cover', 'set_cover_position'],
  media_player: ['media_play_pause', 'media_play', 'media_pause', 'volume_set', 'turn_on', 'turn_off'],
  vacuum: ['start', 'pause', 'return_to_base'],
  scene: ['turn_on'],
  button: ['press'],
};

/** The attributes the page sees. A camera's access_token, entity pictures and the like never leave this server. */
export const ATTRIBUTES = new Set([
  'friendly_name', 'device_class', 'unit_of_measurement', 'brightness', 'color_mode', 'supported_color_modes',
  'current_temperature', 'temperature', 'target_temp_low', 'target_temp_high', 'min_temp', 'max_temp',
  'target_temp_step', 'hvac_modes', 'hvac_action', 'current_humidity', 'preset_mode', 'fan_mode', 'percentage',
  'current_position', 'media_title', 'media_artist', 'app_name', 'source', 'volume_level', 'is_volume_muted',
  'battery_level', 'status', 'fan_speed', 'event_type',
]);

export function publicState(state) {
  if (!state) return null;
  const attributes = Object.fromEntries(Object.entries(state.attributes ?? {}).filter(([k]) => ATTRIBUTES.has(k)));
  return { entity_id: state.entity_id, state: state.state, attributes, last_changed: state.last_changed };
}

export function allowedService(entityId, service) {
  const domain = String(entityId).split('.')[0];
  return Boolean(SERVICES[domain]?.includes(service));
}

/** One WebSocket to Home Assistant, reconnecting with backoff. Emits 'state' and 'status'. */
export class HaLink extends EventEmitter {
  constructor({ url, token }) {
    super();
    this.url = url.replace(/\/$/, '');
    this.token = token;
    this.status = { connected: false, error: 'starting' };
    this.states = new Map();
    this.registry = { areas: [], devices: [], entities: [] };
    this.pending = new Map();
    this.nextId = 1;
    this.backoff = 1000;
  }

  start() {
    const socket = new WebSocket(this.url.replace(/^http/, 'ws') + '/api/websocket');
    this.socket = socket;
    socket.onmessage = (event) => this.receive(JSON.parse(event.data));
    socket.onclose = () => {
      this.setStatus(false, this.status.error === 'auth_invalid' ? 'auth_invalid' : 'disconnected');
      for (const { reject } of this.pending.values()) reject(new Error('disconnected'));
      this.pending.clear();
      if (this.status.error === 'auth_invalid') return; // a bad token won't get better by retrying
      setTimeout(() => this.start(), this.backoff);
      this.backoff = Math.min(this.backoff * 2, 30000);
    };
    socket.onerror = () => {};
  }

  setStatus(connected, error = null) {
    this.status = { connected, error };
    this.emit('status', this.status);
  }

  send(message) {
    const id = this.nextId++;
    this.socket.send(JSON.stringify({ id, ...message }));
    return new Promise((resolve, reject) => this.pending.set(id, { resolve, reject }));
  }

  async receive(message) {
    if (message.type === 'auth_required') return this.socket.send(JSON.stringify({ type: 'auth', access_token: this.token }));
    if (message.type === 'auth_invalid') return this.setStatus(false, 'auth_invalid');
    if (message.type === 'auth_ok') return this.ready();
    if (message.type === 'event' && message.event?.event_type === 'state_changed') {
      const next = message.event.data.new_state;
      if (next) this.states.set(next.entity_id, next); else this.states.delete(message.event.data.entity_id);
      return this.emit('state', publicState(next) ?? { entity_id: message.event.data.entity_id, state: 'removed', attributes: {} });
    }
    if (message.type === 'result' && this.pending.has(message.id)) {
      const { resolve, reject } = this.pending.get(message.id);
      this.pending.delete(message.id);
      if (message.success) resolve(message.result); else reject(Object.assign(new Error(message.error?.message ?? 'failed'), { code: message.error?.code }));
    }
  }

  async ready() {
    try {
      const [areas, devices, entities, states] = await Promise.all([
        this.send({ type: 'config/area_registry/list' }),
        this.send({ type: 'config/device_registry/list' }),
        this.send({ type: 'config/entity_registry/list' }),
        this.send({ type: 'get_states' }),
      ]);
      this.registry = { areas, devices, entities };
      this.states = new Map(states.map((s) => [s.entity_id, s]));
      // Which cameras can give a still picture: ones that only stream WebRTC (Nest's) get a placeholder instead.
      this.streams = new Map();
      for (const s of states.filter((s) => s.entity_id.startsWith('camera.'))) {
        const caps = await this.send({ type: 'camera/capabilities', entity_id: s.entity_id }).catch(() => null);
        if (caps?.frontend_stream_types) this.streams.set(s.entity_id, caps.frontend_stream_types);
      }
      await this.send({ type: 'subscribe_events', event_type: 'state_changed' });
      this.backoff = 1000;
      this.setStatus(true);
    } catch (error) {
      this.setStatus(false, `setup failed: ${error.code ?? error.message}`);
      this.socket.close();
    }
  }

  snapshot() {
    const deviceArea = new Map(this.registry.devices.map((d) => [d.id, d.area_id]));
    const entities = this.registry.entities
      .filter((e) => !e.disabled_by && !e.hidden_by && !e.entity_category && this.states.has(e.entity_id))
      .map((e) => ({
        entity_id: e.entity_id,
        name: e.name ?? e.original_name ?? this.states.get(e.entity_id)?.attributes?.friendly_name ?? e.entity_id,
        device_id: e.device_id ?? null,
        area_id: e.area_id ?? deviceArea.get(e.device_id) ?? null,
        ...(this.streams?.has(e.entity_id) ? { stream: this.streams.get(e.entity_id).includes('hls') ? 'hls' : this.streams.get(e.entity_id)[0] } : {}),
        ...publicState(this.states.get(e.entity_id)),
      }));
    return {
      areas: this.registry.areas.map((a) => ({ area_id: a.area_id, name: a.name, floor_id: a.floor_id ?? null })),
      devices: this.registry.devices.filter((d) => !d.disabled_by).map((d) => ({
        id: d.id, name: d.name_by_user ?? d.name ?? 'Device', area_id: d.area_id ?? null, manufacturer: d.manufacturer, model: d.model,
      })),
      entities,
    };
  }

  async callService(entityId, service, data = {}) {
    const domain = entityId.split('.')[0];
    await this.send({ type: 'call_service', domain, service, service_data: data, target: { entity_id: entityId } });
  }

  async camera(entityId) {
    const response = await fetch(`${this.url}/api/camera_proxy/${encodeURIComponent(entityId)}`, { headers: { Authorization: `Bearer ${this.token}` } });
    if (!response.ok) throw new Error(`camera ${response.status}`);
    return { type: response.headers.get('content-type') ?? 'image/jpeg', body: Buffer.from(await response.arrayBuffer()) };
  }
}

const json = (res, status, body) => {
  res.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  res.end(JSON.stringify(body));
};

async function readBody(req, limit = 20000) {
  let text = '';
  for await (const chunk of req) { text += chunk; if (text.length > limit) throw new Error('too large'); }
  return JSON.parse(text || '{}');
}

/** Only this Mac's own page may use the bridge: checks Host on everything, and Origin on anything that changes state. */
export function trusted(req, port) {
  const hosts = [`127.0.0.1:${port}`, `localhost:${port}`];
  if (!hosts.includes(req.headers.host)) return false;
  if (req.method === 'GET') return true;
  const origin = req.headers.origin;
  return Boolean(origin) && hosts.some((h) => origin === `http://${h}`) && /application\/json/.test(req.headers['content-type'] ?? '');
}

export function haBridge({ houseDir }) {
  return {
    name: 'ha-bridge',
    async configureServer(server) {
      const port = server.config.server.port;
      let link;
      if (process.env.HA_MOCK) {
        link = mockHomeAssistant();
      } else {
        let token = null;
        try { token = (await readFile(TOKEN_FILE, 'utf8')).trim(); } catch { /* no token yet */ }
        if (token) {
          let url = process.env.HA_URL;
          if (!url) try { url = (await readFile(URL_FILE, 'utf8')).trim(); } catch { url = 'http://homeassistant.local:8123'; }
          link = new HaLink({ url, token });
          link.start();
        }
      }
      // In demo mode, room choices point at pretend areas, so they stay in memory instead of the house folder.
      const roomsFile = houseDir && !process.env.HA_MOCK ? path.join(houseDir, 'areas.json') : null;
      let demoRooms = {};

      server.middlewares.use(async (req, res, next) => {
        if (!req.url.startsWith('/ha/')) return next();
        if (!trusted(req, port)) return json(res, 403, { error: 'forbidden' });
        const url = new URL(req.url, 'http://local');
        try {
          if (url.pathname === '/ha/status') {
            return json(res, 200, link ? { ...link.status, mock: Boolean(process.env.HA_MOCK) } : { connected: false, error: 'no_token' });
          }
          if (url.pathname === '/ha/rooms') {
            let map = roomsFile ? {} : demoRooms;
            if (roomsFile) try { map = JSON.parse(await readFile(roomsFile, 'utf8')); } catch { /* none yet */ }
            if (req.method === 'POST') {
              const { key, area_id: areaId } = await readBody(req);
              if (typeof key !== 'string' || key.length > 200) return json(res, 400, { error: 'bad key' });
              if (areaId) map[key] = String(areaId); else delete map[key];
              if (roomsFile) await writeFile(roomsFile, JSON.stringify(map, null, 1) + '\n'); else demoRooms = map;
            }
            return json(res, 200, map);
          }
          // The site editor saves the lot drawing into house.json, keeping the previous file as house.json.bak.
          if (url.pathname === '/ha/site' && req.method === 'POST') {
            if (!houseDir) return json(res, 400, { error: 'no house folder' });
            const { site } = await readBody(req, 2_000_000);
            if (!site || typeof site !== 'object' || !Array.isArray(site.features ?? []) || !Array.isArray(site.places ?? [])) return json(res, 400, { error: 'bad site' });
            const file = path.join(houseDir, 'house.json');
            const text = await readFile(file, 'utf8');
            const house = JSON.parse(text);
            await writeFile(file + '.bak', text);
            house.site = site;
            await writeFile(file, JSON.stringify(house, null, 1) + '\n');
            return json(res, 200, { ok: true });
          }
          if (!link?.status.connected) return json(res, 503, { error: link?.status.error ?? 'no_token' });
          if (url.pathname === '/ha/snapshot') return json(res, 200, link.snapshot());
          if (url.pathname === '/ha/events') {
            res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store', Connection: 'keep-alive' });
            const onState = (state) => res.write(`data: ${JSON.stringify(state)}\n\n`);
            const onStatus = (status) => res.write(`event: status\ndata: ${JSON.stringify(status)}\n\n`);
            link.on('state', onState);
            link.on('status', onStatus);
            const ping = setInterval(() => res.write(': ping\n\n'), 25000);
            req.on('close', () => { clearInterval(ping); link.off('state', onState); link.off('status', onStatus); });
            return;
          }
          if (url.pathname === '/ha/service' && req.method === 'POST') {
            const { entity_id: entityId, service, data } = await readBody(req);
            const known = link.snapshot().entities.some((e) => e.entity_id === entityId);
            if (!known || !allowedService(entityId, service)) return json(res, 403, { error: 'not allowed' });
            await link.callService(entityId, service, data && typeof data === 'object' ? data : {});
            return json(res, 200, { ok: true });
          }
          const camera = url.pathname.match(/^\/ha\/camera\/(camera\.[\w]+)$/);
          if (camera && link.snapshot().entities.some((e) => e.entity_id === camera[1])) {
            const picture = await link.camera(camera[1]);
            res.writeHead(200, { 'Content-Type': picture.type, 'Cache-Control': 'no-store' });
            return res.end(picture.body);
          }
          return json(res, 404, { error: 'not found' });
        } catch (error) {
          return json(res, 502, { error: error.message });
        }
      });
    },
  };
}
