// The room and device control panel, drawn like a panel schedule on the blueprint: schematic symbols, ruled boxes,
// lettering. It's plain HTML, so it works the same whether html-in-canvas draws it into the scene or it sits beside it.
import { feetInches, squareFeet } from './house.js';

const esc = (s) => String(s ?? '').replace(/[&<>"]/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' })[c]);
const svg = (body, size = 26) => `<svg viewBox="0 0 26 26" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round">${body}</svg>`;

/** Schematic symbols, the way an electrical drawing marks fixtures. */
const GLYPHS = {
  light: (on) => svg(`<circle cx="13" cy="13" r="8"/><path d="M7.3 7.3l11.4 11.4M18.7 7.3L7.3 18.7"/>${on ? '<circle cx="13" cy="13" r="11.5" stroke-dasharray="2 2.5"/>' : ''}`),
  switch: (on) => svg(`<circle cx="5" cy="17" r="1.6"/><circle cx="21" cy="17" r="1.6"/><path d="M6.4 16.2 ${on ? 'L19.5 16.6' : 'L18 8'}"/>`),
  fan: () => svg('<circle cx="13" cy="13" r="2"/><path d="M13 11c0-4 3-6 5-4s-1 4-5 4zM14.7 14c3.5 2 3.7 5.6.9 6.2s-3-3-.9-6.2zM11.3 14c-3.5 2-6.7.4-5.8-2.3s4.4-1.5 5.8 2.3z"/>'),
  lock: (on) => svg(`<rect x="6" y="12" width="14" height="10" rx="1"/><path d="M9 12V9a4 4 0 0 1 8 0${on ? 'v3' : 'V7'}"/><path d="M13 16v2.5"/>`),
  climate: () => svg('<circle cx="13" cy="13" r="10"/><path d="M9 9h8M13 9v9"/>'),
  cover: () => svg('<path d="M3 22V7l10-4 10 4v15"/><path d="M6 11h14M6 14h14M6 17h14M6 20h14"/>'),
  media_player: () => svg('<rect x="3" y="5" width="20" height="13" rx="1"/><path d="M9 22h8M13 18v4"/>'),
  vacuum: () => svg('<circle cx="13" cy="13" r="9.5"/><circle cx="13" cy="13" r="3"/><path d="M6.5 9.5h13"/>'),
  camera: () => svg('<rect x="3" y="8" width="14" height="11" rx="1"/><path d="M17 12l6-3v9l-6-3z"/>'),
  scene: () => svg('<path d="M13 3l2.6 6.4L22 10l-5 4.3L18.5 21 13 17.4 7.5 21 9 14.3 4 10l6.4-.6z"/>'),
  button: () => svg('<circle cx="13" cy="13" r="9"/><circle cx="13" cy="13" r="4"/>'),
  sensor: () => svg('<path d="M13 3l10 10-10 10L3 13z"/>'),
  event: () => svg('<path d="M8 18V12a5 5 0 0 1 10 0v6l2 2H6z"/><path d="M11 22h4"/>'),
  binary_sensor: (on) => svg(`<path d="M13 3l10 10-10 10L3 13z"/>${on ? '<path d="M13 3L3 13l10 10z" fill="currentColor"/>' : ''}`),
};
GLYPHS.input_boolean = GLYPHS.switch;

const domainOf = (e) => e.entity_id.split('.')[0];
const isOn = (e) => ['on', 'open', 'playing', 'unlocked', 'cleaning', 'heat', 'cool', 'heat_cool'].includes(e.state);
const glyph = (e) => (GLYPHS[domainOf(e)] ?? GLYPHS.sensor)(domainOf(e) === 'lock' ? e.state === 'locked' : isOn(e));

const BINARY_WORDS = { door: ['CLOSED', 'OPEN'], window: ['CLOSED', 'OPEN'], garage_door: ['CLOSED', 'OPEN'], opening: ['CLOSED', 'OPEN'],
  motion: ['CLEAR', 'MOTION'], occupancy: ['CLEAR', 'OCCUPIED'], moisture: ['DRY', 'WET'], smoke: ['CLEAR', 'SMOKE'], battery: ['OK', 'LOW'] };

export function summary(e) {
  const a = e.attributes ?? {};
  switch (domainOf(e)) {
    case 'light': return e.state === 'on' && a.brightness ? `ON · ${Math.round((a.brightness / 255) * 100)}%` : e.state.toUpperCase();
    case 'climate': return `${a.current_temperature ?? '–'}° · ${(a.hvac_action ?? e.state).toUpperCase()}`;
    case 'binary_sensor': { const w = BINARY_WORDS[a.device_class] ?? ['OFF', 'ON']; return w[e.state === 'on' ? 1 : 0]; }
    case 'event': {
      const t = Date.parse(e.state);
      if (Number.isNaN(t)) return 'NO EVENTS YET';
      const minutes = Math.round((Date.now() - t) / 60000);
      const ago = minutes < 1 ? 'JUST NOW' : minutes < 60 ? `${minutes} MIN AGO` : minutes < 1440 ? `${Math.round(minutes / 60)} H AGO` : `${Math.round(minutes / 1440)} D AGO`;
      return `${String(a.event_type ?? 'event').replace(/_/g, ' ').toUpperCase()} · ${ago}`;
    }
    case 'sensor': return `${e.state}${a.unit_of_measurement ? ` ${a.unit_of_measurement}` : ''}`.toUpperCase();
    case 'media_player': return a.media_title ? `${e.state.toUpperCase()} · ${a.media_title}` : e.state.toUpperCase();
    case 'cover': return a.current_position !== undefined && e.state !== 'closed' ? `${e.state.toUpperCase()} · ${a.current_position}%` : e.state.toUpperCase();
    default: return String(e.state).toUpperCase();
  }
}

const act = (e, service, data, label, cls = '') =>
  `<button class="act ${cls}" data-entity="${esc(e.entity_id)}" data-service="${service}" data-data='${esc(JSON.stringify(data ?? {}))}'>${label}</button>`;

/** A drafting scale: tick marks you tap. Dragging doesn't work reliably on a drawn element, taps do. */
function ruler(e, service, key, value, { from = 0, to = 100, step = 10, scale = 1, label = '%' } = {}) {
  let ticks = '';
  for (let v = from; v <= to; v += step) {
    const on = value !== null && value >= v - step / 2;
    ticks += `<button class="tick ${on ? 'on' : ''}" data-entity="${esc(e.entity_id)}" data-service="${service}" data-data='${esc(JSON.stringify({ [key]: v * scale }))}'><i></i>${v % (step * 2) === 0 ? `<small>${v}</small>` : ''}</button>`;
  }
  return `<div class="ruler" title="${label}">${ticks}</div>`;
}

function dial(e) {
  const a = e.attributes;
  const lo = a.min_temp ?? 50, hi = a.max_temp ?? 90;
  const angle = (t) => -120 + ((Math.min(hi, Math.max(lo, t)) - lo) / (hi - lo)) * 240;
  const point = (deg, r) => { const rad = ((deg - 90) * Math.PI) / 180; return [50 + r * Math.cos(rad), 54 + r * Math.sin(rad)]; };
  let ticks = '';
  for (let t = lo; t <= hi; t += (hi - lo) / 24) {
    const major = Math.round(t - lo) % 10 === 0;
    const [x1, y1] = point(angle(t), 40), [x2, y2] = point(angle(t), major ? 33 : 36);
    ticks += `<line x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}"/>`;
  }
  const current = a.current_temperature, target = a.temperature;
  const [nx, ny] = point(angle(current ?? lo), 30);
  const marker = target != null ? (() => { const [tx, ty] = point(angle(target), 44); return `<circle cx="${tx}" cy="${ty}" r="3" fill="currentColor"/>`; })() : '';
  return `<svg class="dial" viewBox="0 0 100 80" stroke="currentColor" fill="none" stroke-width="1">
    <path d="M${point(-120, 40).join(' ')} A40 40 0 1 1 ${point(120, 40).join(' ')}"/>${ticks}${marker}
    <line x1="50" y1="54" x2="${nx}" y2="${ny}" stroke-width="1.6"/><circle cx="50" cy="54" r="2.5" fill="currentColor"/>
    <text x="50" y="76" text-anchor="middle" fill="currentColor" stroke="none" font-size="11">${current ?? '–'}°</text></svg>`;
}

function controls(e, ui) {
  const a = e.attributes ?? {};
  const domain = domainOf(e);
  const head = `<div class="ctl-head">${glyph(e)}<b>${esc(e.name)}</b><span>${esc(summary(e))}</span></div>`;
  let body = '';
  if (['light', 'switch', 'input_boolean', 'fan'].includes(domain)) {
    body += `<div class="row">${act(e, 'toggle', {}, `${GLYPHS.switch(isOn(e))}<span>${isOn(e) ? 'ON' : 'OFF'}</span>`, `big ${isOn(e) ? 'on' : ''}`)}</div>`;
    const dims = (a.supported_color_modes ?? []).some((m) => m !== 'onoff');
    if (domain === 'light' && dims) body += ruler(e, 'turn_on', 'brightness_pct', e.state === 'on' ? Math.round(((a.brightness ?? 0) / 255) * 100) : 0, { from: 10, to: 100, step: 10 });
    if (domain === 'fan' && a.percentage !== undefined) body += ruler(e, 'set_percentage', 'percentage', e.state === 'on' ? a.percentage : 0, { from: 0, to: 100, step: 25 });
  } else if (domain === 'lock') {
    const locked = e.state === 'locked';
    const confirming = ui.confirm === e.entity_id;
    body += `<div class="row">${locked
      ? act(e, 'unlock', {}, confirming ? 'TAP AGAIN TO UNLOCK' : 'UNLOCK', `big ${confirming ? 'warn' : ''}`)
      : act(e, 'lock', {}, 'LOCK', 'big')}</div>`;
  } else if (domain === 'climate') {
    const step = a.target_temp_step ?? 1;
    body += `<div class="climate">${dial(e)}<div class="setpoint">`;
    if (a.temperature != null) {
      body += `<small>SET TO</small><b>${a.temperature}°</b><div class="row">${act(e, 'set_temperature', { temperature: a.temperature - step }, '−')}${act(e, 'set_temperature', { temperature: a.temperature + step }, '+')}</div>`;
    } else if (a.target_temp_low != null) {
      body += `<small>HEAT ${a.target_temp_low}° · COOL ${a.target_temp_high}°</small>`;
    }
    body += `</div></div><div class="row modes">${(a.hvac_modes ?? []).map((m) => act(e, 'set_hvac_mode', { hvac_mode: m }, m.replace('_', '/').toUpperCase(), e.state === m ? 'on' : '')).join('')}</div>`;
    if (a.current_humidity != null) body += `<p class="fine">HUMIDITY ${a.current_humidity}%</p>`;
  } else if (domain === 'cover') {
    body += `<div class="gauge"><i style="width:${a.current_position ?? (e.state === 'open' ? 100 : 0)}%"></i></div><div class="row">${act(e, 'open_cover', {}, 'OPEN')}${act(e, 'stop_cover', {}, 'STOP')}${act(e, 'close_cover', {}, 'CLOSE')}</div>`;
  } else if (domain === 'media_player') {
    if (a.media_title || a.app_name) body += `<p class="fine">${esc(a.app_name ?? '')}${a.media_artist ? ` · ${esc(a.media_artist)}` : ''}</p>`;
    body += `<div class="row">${act(e, 'media_play_pause', {}, e.state === 'playing' ? 'PAUSE' : 'PLAY', 'big')}${act(e, e.state === 'off' ? 'turn_on' : 'turn_off', {}, 'POWER')}</div>`;
    if (a.volume_level != null) body += ruler(e, 'volume_set', 'volume_level', Math.round(a.volume_level * 100), { from: 0, to: 100, step: 10, scale: 0.01 });
  } else if (domain === 'vacuum') {
    body += `<p class="fine">${esc(a.status ?? '')}${a.battery_level != null ? ` · BATTERY ${a.battery_level}%` : ''}</p><div class="row">${act(e, 'start', {}, 'START')}${act(e, 'pause', {}, 'PAUSE')}${act(e, 'return_to_base', {}, 'DOCK')}</div>`;
  } else if (domain === 'camera') {
    // Cameras that only stream live video (WebRTC, as Nest's do) have no still picture to show, just a placeholder.
    if (e.stream === 'web_rtc') {
      body += `<p class="fine">Live video only: this camera has no still picture.${ui.cameraLink ? ` <a href="${esc(ui.cameraLink)}" target="_blank" rel="noopener">Open live view</a>` : ''}</p>`;
    } else {
      body += `<img class="cam" src="${esc(ui.cameraUrl(e.entity_id, ui.cameraTick))}" alt="">`;
    }
  } else if (domain === 'scene') {
    body += `<div class="row">${act(e, 'turn_on', {}, 'ACTIVATE')}</div>`;
  } else if (domain === 'button') {
    body += `<div class="row">${act(e, 'press', {}, 'PRESS')}</div>`;
  }
  return `<section class="ctl">${head}${body}</section>`;
}

/** The whole panel for a room: its devices, and the chosen device's controls. */
export function renderPanel(ui, home) {
  const { floor, room } = ui;
  const where = floor.label === 'Site' ? 'OUTSIDE' : `${esc(floor.label)} · EL. ${feetInches(floor.elevation)}`;
  const title = `<header><button class="close" data-close>×</button><small>${where}</small><h2>${esc(room.name)}</h2>${room.area ? `<span>${squareFeet(room.area)}</span>` : ''}</header>`;
  if (!home.status.connected) {
    const why = home.status.error === 'no_token'
      ? 'Not connected to Home Assistant yet: no token. Run scripts/set-ha-token.sh, then restart.'
      : home.status.error === 'auth_invalid' ? 'Home Assistant refused the token. Make a new one and run scripts/set-ha-token.sh again.'
        : `Home Assistant isn't answering (${esc(home.status.error)}).`;
    return `${title}<p class="fine">${why}</p>`;
  }
  const { area, chosen } = home.areaFor(floor.label, room.name, ui.sameName);
  if (!area || ui.choosingArea) {
    const options = home.areas.map((a) => `<button class="act" data-area="${esc(a.area_id)}">${esc(a.name)}</button>`).join('');
    return `${title}<p class="fine">Which Home Assistant area is this room?</p><div class="row wrap">${options || '<p class="fine">Home Assistant has no areas yet.</p>'}</div>
      ${chosen || area ? '<div class="row"><button class="act" data-area="">FORGET THE CHOICE</button></div>' : ''}`;
  }
  const devices = home.devicesIn(area.area_id);
  const list = devices.map((d) => {
    const lead = d.entities[0];
    return `<button class="device ${ui.device === d.id ? 'on' : ''}" data-device="${esc(d.id)}">${glyph(lead)}<b>${esc(d.name)}</b><span>${esc(summary(lead))}</span></button>`;
  }).join('') || '<p class="fine">No devices in this area.</p>';
  const selected = devices.find((d) => d.id === ui.device);
  return `${title}<div class="area">HOME ASSISTANT AREA: ${esc(area.name)} <button class="link" data-rechoose>CHANGE</button></div>
    <div class="devices">${list}</div>${selected ? selected.entities.map((e) => controls(e, ui)).join('') : ''}${ui.error ? `<p class="fine warn">${esc(ui.error)}</p>` : ''}`;
}
