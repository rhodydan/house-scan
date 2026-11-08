# House blueprint

A 3D view of a scanned house, drawn like a blueprint: white linework and shaded planes on blue paper, with lettering
and callouts in a draftsman's hand. Spin it, zoom it, pull the floors apart, or tap a floor to bring it forward with
dimension strings on its outside walls. Plan view opens on one floor and reads as a flat drawing.

It reads House Scan's floor JSON exports plus a `house.json` that says how the floors stack. The house itself never
lives in this repo: point the dev server at a folder elsewhere, or drop the files onto the page.

```sh
npm install
HOUSE_DIR="/path/to/Viewer data" npm run dev     # http://127.0.0.1:5199, this Mac only
node scripts/export.mjs "/path/to/Viewer data" "/path/outside/the/repo"   # GLB, USDZ, OBJ, STL and a DXF per floor
```

`?intro=0`, `?view=plan|axon|side`, `?expand=0..1` and `?focus=<floor index>` set the opening state.

## Home Assistant

Tap a floor for its plan, then a room for its devices. The room names on the floor and the control panel are HTML drawn
into the 3D scene with [html-in-canvas](https://github.com/WICG/html-in-canvas), so they sit on the drawing and still
take clicks; browsers without it get the same HTML over the canvas instead. See `src/drawn.js`.

The dev server talks to Home Assistant for the page (`server/ha-bridge.js`), so the token never reaches the browser:

1. In Home Assistant, make a non-admin user for the dashboard, sign in as it, and create a long-lived access token
   (Profile > Security). Copy it.
2. Run `scripts/set-ha-token.sh`. It stores the token from the clipboard in `~/.config/house-blueprint/ha-token`,
   readable only by you, and clears the clipboard.
3. If Home Assistant isn't at `http://homeassistant.local:8123`, put its address in `~/.config/house-blueprint/ha-url`
   or set `HA_URL`.

The bridge answers only this machine's page (it checks Host and Origin), passes on a fixed list of actions, and strips
attributes such as camera access tokens. Which Home Assistant area each scanned room is gets saved in `areas.json` in the
house folder. `HA_MOCK=1` runs against invented devices instead, and `node scripts/e2e.mjs` checks, in real Chrome
against the mock, that a click on a drawn room label opens its panel and a tap on a drawn switch changes the device.

## house.json

```json
{
  "format": "house-blueprint/1",
  "name": "Sample House",
  "floors": [
    { "file": "Sample-Main.json", "label": "Main floor", "angleDegrees": 11.3, "offset": [0, 0], "elevation": 3.0, "floorY": -1.37 }
  ],
  "corrections": {
    "Sample-Garage.json": {
      "removeWalls": ["<wall id>"],
      "addWalls": [{ "from": [0, 0], "to": [4, 0], "height": 2.7 }],
      "addDoors": [{ "center": [2, 0], "along": [1, 0], "width": 2.743, "height": 2.515, "label": "garage door" }],
      "moveDoorsOntoWall": { "from": "<removed wall id>", "line": [[0, 0], [4, 0]] },
      "callouts": [{ "text": "landing, 2 steps up", "nearDoorsOnWall": ["<wall id>"] }]
    }
  }
}
```

- **Floors:** each floor is turned by `angleDegrees` (a positive angle turns +X towards +Z), shifted by `offset` in
  metres, and set at `elevation` above the lowest floor. `floorY` is the scan's own floor height, from the export.
- **Corrections:** these are in that floor's own scan frame, before it's turned. They fix what the scanner couldn't
  see, and the export JSON itself is never edited.
- **Site:** `site.features` draws the lot in the house's frame: `property`, `wall`, `driveway`, `lawn`, `bed`, `path`,
  `steps`, `patio`, `court` and `structure` take `points`; `pool` takes `center` and `radius`. Each can have an
  `elevation` (a sloping lot puts the back yard and the driveway at different heights), a `name` to letter it, and
  structures a `height` and `roof: "pyramid"`. `site.places` are outdoor spots (`name`, `at`, `elevation`) that open
  their Home Assistant area's devices, matched by name like rooms. The site gets its own entry in the floor rail.
- **Links:** `links.cameras` is where to watch live video, such as a hub's camera page. Cameras that only stream
  WebRTC (Nest's, for example) have no still picture for the panel, so it offers this link instead.
- **North:** `north.plusXBearingDegrees` is the compass bearing of the house's +X; the title block's arrow uses it.
- **Top views:** X runs right and Z runs down the page. RoomPlan is Y-up and right-handed, so drawing Z up the page
  mirrors the house.

Each floor is scanned on its own, so the poses have to be fitted. Wall matching alone can't choose between near-equal
fits. Anchors settle it: stairs over stairs, matching doors between attached spaces, and rooms known to be over other
rooms.
