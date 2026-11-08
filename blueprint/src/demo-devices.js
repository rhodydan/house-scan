// Invented Home Assistant areas, devices and states, and how actions change them. Shared by the dev server's mock mode
// (HA_MOCK=1) and the public demo, which runs entirely in the browser. Nothing here describes a real home.

const AREA_NAMES = {
  kitchen: 'Kitchen', living_room: 'Living Room', dining: 'Dining Room', office: 'Office', hallway: 'Hallway',
  powder: 'Powder Room', primary: 'Primary Bedroom', bedroom_2: 'Bedroom 2', bedroom_3: 'Bedroom 3', bathroom: 'Bathroom',
  upstairs: 'Upstairs Hall', laundry: 'Laundry', garage: 'Garage', theater: 'Theater', foyer: 'Foyer',
};

// [device id, name, area, [[entity_id, state, attributes]]]
const DEVICES = [
  ['d1', 'Ceiling lights', 'kitchen', [['light.kitchen_ceiling', 'on', { friendly_name: 'Ceiling lights', brightness: 180, supported_color_modes: ['brightness'] }]]],
  ['d2', 'Island pendants', 'kitchen', [['switch.island_pendants', 'off', { friendly_name: 'Island pendants' }]]],
  ['d3', 'Fridge door', 'kitchen', [['binary_sensor.fridge_door', 'off', { friendly_name: 'Fridge door', device_class: 'door' }]]],
  ['d4', 'Thermostat', 'hallway', [['climate.hallway', 'heat', { friendly_name: 'Thermostat', current_temperature: 68.5, temperature: 70, min_temp: 50, max_temp: 90, hvac_modes: ['off', 'heat', 'cool', 'heat_cool'], hvac_action: 'heating', current_humidity: 41 }]]],
  ['d5', 'Robot vacuum', 'hallway', [['vacuum.robot', 'docked', { friendly_name: 'Robot vacuum', battery_level: 96, status: 'Charging' }]]],
  ['d6', 'Front door lock', 'hallway', [['lock.front_door', 'locked', { friendly_name: 'Front door lock' }], ['sensor.front_door_battery', '82', { friendly_name: 'Lock battery', unit_of_measurement: '%', device_class: 'battery' }]]],
  ['d7', 'TV', 'living_room', [['media_player.living_room_tv', 'playing', { friendly_name: 'TV', media_title: 'Nature documentary', app_name: 'Streaming', volume_level: 0.3 }]]],
  ['d8', 'Floor lamp', 'living_room', [['light.floor_lamp', 'off', { friendly_name: 'Floor lamp', brightness: null, supported_color_modes: ['brightness'] }]]],
  ['d9', 'Desk lamp', 'office', [['light.desk_lamp', 'on', { friendly_name: 'Desk lamp', brightness: 255, supported_color_modes: ['onoff'] }]]],
  ['d10', 'Printer', 'office', [['sensor.printer_status', 'idle', { friendly_name: 'Printer' }], ['sensor.printer_black_toner', '64', { friendly_name: 'Black toner', unit_of_measurement: '%' }]]],
  ['d11', 'Garage door', 'garage', [['cover.garage_door', 'closed', { friendly_name: 'Garage door', device_class: 'garage', current_position: 0 }]]],
  ['d12', 'Porch camera', 'hallway', [['camera.porch', 'idle', { friendly_name: 'Porch camera' }], ['binary_sensor.porch_motion', 'off', { friendly_name: 'Motion', device_class: 'motion' }]]],
  ['d13', 'Washer', 'laundry', [['sensor.washer_state', 'running', { friendly_name: 'Washer' }], ['sensor.washer_time_left', '23', { friendly_name: 'Time left', unit_of_measurement: 'min' }]]],
  ['d14', 'Ceiling fan', 'primary', [['fan.primary_bedroom', 'on', { friendly_name: 'Ceiling fan', percentage: 33 }]]],
  ['d15', 'Projector', 'theater', [['switch.projector', 'off', { friendly_name: 'Projector' }], ['scene.movie_night', 'unknown', { friendly_name: 'Movie night' }]]],
  ['d16', 'Chandelier', 'dining', [['light.dining_chandelier', 'off', { friendly_name: 'Chandelier', brightness: null, supported_color_modes: ['brightness'] }]]],
  ['d17', 'Dinner scene', 'dining', [['scene.dinner', 'unknown', { friendly_name: 'Dinner' }]]],
  ['d18', 'Bedside lamp', 'primary', [['light.primary_bedside', 'off', { friendly_name: 'Bedside lamp', brightness: null, supported_color_modes: ['brightness'] }]]],
  ['d19', 'Blinds', 'primary', [['cover.primary_blinds', 'open', { friendly_name: 'Blinds', current_position: 100 }]]],
  ['d20', 'Night light', 'bedroom_2', [['light.night_light', 'on', { friendly_name: 'Night light', brightness: 40, supported_color_modes: ['brightness'] }]]],
  ['d21', 'Speaker', 'bedroom_3', [['media_player.bedroom_speaker', 'paused', { friendly_name: 'Speaker', media_title: 'Rain sounds', volume_level: 0.2 }]]],
  ['d22', 'Window', 'bedroom_3', [['binary_sensor.bedroom_3_window', 'on', { friendly_name: 'Window', device_class: 'window' }]]],
  ['d23', 'Exhaust fan', 'bathroom', [['switch.bathroom_fan', 'off', { friendly_name: 'Exhaust fan' }], ['sensor.bathroom_humidity', '58', { friendly_name: 'Humidity', unit_of_measurement: '%' }]]],
  ['d24', 'Vanity light', 'powder', [['light.powder_vanity', 'off', { friendly_name: 'Vanity light', brightness: null, supported_color_modes: ['onoff'] }]]],
  ['d25', 'Hall lights', 'upstairs', [['light.upstairs_hall', 'off', { friendly_name: 'Hall lights', brightness: null, supported_color_modes: ['brightness'] }]]],
  ['d26', 'Dryer', 'laundry', [['sensor.dryer_state', 'idle', { friendly_name: 'Dryer' }]]],
];

/** A fresh copy of the pretend home. */
export function demoHome() {
  const areas = Object.entries(AREA_NAMES).map(([area_id, name]) => ({ area_id, name, floor_id: null }));
  const devices = DEVICES.map(([id, name, area_id]) => ({ id, name, area_id, manufacturer: 'Example', model: 'Demo' }));
  const states = new Map();
  const entities = [];
  for (const [id, , area_id, list] of DEVICES) {
    for (const [entity_id, state, attributes] of list) {
      states.set(entity_id, { entity_id, state, attributes: { ...attributes }, last_changed: new Date().toISOString() });
      entities.push({ entity_id, name: attributes.friendly_name, device_id: id, area_id });
    }
  }
  return { areas, devices, states, entities };
}

/** What an action does to a pretend device. Returns the new state, or null for an action it doesn't know. */
export function applyService(current, service, data = {}) {
  const set = (state, changes = {}) => ({ ...current, state: state ?? current.state, attributes: { ...current.attributes, ...changes }, last_changed: new Date().toISOString() });
  const flip = current.state === 'on' ? 'off' : 'on';
  switch (service) {
    case 'toggle': return set(flip);
    case 'turn_on':
      if (data.brightness_pct !== undefined) return set('on', { brightness: Math.round(data.brightness_pct * 2.55) });
      if (data.percentage !== undefined) return set('on', { percentage: data.percentage });
      return set(current.entity_id.startsWith('scene.') ? current.state : 'on');
    case 'turn_off': return set('off');
    case 'set_percentage': return set(data.percentage > 0 ? 'on' : 'off', { percentage: data.percentage });
    case 'lock': return set('locked');
    case 'unlock': return set('unlocked');
    case 'set_temperature': return set(null, { temperature: data.temperature });
    case 'set_hvac_mode': return set(data.hvac_mode, { hvac_action: data.hvac_mode === 'off' ? 'off' : 'idle' });
    case 'open_cover': return set('open', { current_position: 100 });
    case 'close_cover': return set('closed', { current_position: 0 });
    case 'stop_cover': return set(null);
    case 'media_play_pause': return set(current.state === 'playing' ? 'paused' : 'playing');
    case 'volume_set': return set(null, { volume_level: data.volume_level });
    case 'start': return set('cleaning', { status: 'Cleaning' });
    case 'return_to_base': return set('returning', { status: 'Returning' });
    case 'pause': return set('paused', { status: 'Paused' });
    case 'press': return set(null);
    default: return null;
  }
}

/** A drawn stand-in for a camera picture. */
export function demoCameraPicture() {
  const time = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit', second: '2-digit' });
  return `<svg xmlns="http://www.w3.org/2000/svg" width="640" height="360"><rect width="640" height="360" fill="#2b3440"/><path d="M0 300 L640 300" stroke="#55606e" stroke-width="2"/><rect x="250" y="150" width="140" height="150" fill="none" stroke="#7b8796" stroke-width="3"/><text x="320" y="70" fill="#cfd8e3" font-family="sans-serif" font-size="26" text-anchor="middle">Pretend camera · ${time}</text></svg>`;
}
