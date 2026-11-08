# House Scan

A personal iPhone app for scanning a house with LiDAR. Projects hold floors, floors hold rooms. Each room is scanned with
Apple's RoomPlan, and a floor's rooms merge into one model that exports as USDZ, a PDF and PNG floor plan, and JSON.
Rooms can also hold an insurance inventory, and projects hold site notes: a photo with GPS, compass heading and a note.

The app has no accounts, analytics or network code, and Apple says RoomPlan processes scans on the device. Where the
results go after that is up to you: exports go through the share sheet, and the app's data is in your normal iPhone
backups. iOS itself may use Apple's network-assisted location services when you take a site note, which is outside the
app's control.

## Build

```sh
xcodegen                                  # the .xcodeproj and Info.plist are generated from project.yml
scripts/phone.sh install                  # build and install on the iPhone (unlock it first)
scripts/phone.sh test                     # unit tests plus the on-device RoomPlan tests
scripts/check-privacy.sh                  # audit that the app has no network code
```

Simulator tests:

```sh
xcodebuild test -project HouseScan.xcodeproj -scheme HouseScan \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' CODE_SIGNING_ALLOWED=NO
```

Requires iOS 17, for StructureBuilder and shared AR sessions. Set `HOUSE_SCAN_TEAM` to your Apple team ID before running
`xcodegen`, and change the bundle IDs in `project.yml` to a domain you control.

## How merging works

RoomPlan only merges rooms that share a coordinate space. Apple's rules, and how the app follows them:

- **One visit:** rooms share a running AR session. Each room ends with `stop(pauseARSession: false)`.
- **A later visit:** the floor's saved `ARWorldMap` is reloaded and the app waits for ARKit to recognize the place
  before scanning. Stand somewhere you've already scanned.
- **If that fails:** you can start anyway, but those rooms get a new coordinate space. Each room records its space
  (`ScanRecord.spaceID`), so export merges the biggest group and names the rooms it left out.
- **If the app goes to the background mid-visit:** the AR session can't be trusted, so the scan screen stops and asks you
  to reopen it, which relocalizes.

Apple recommends at most 2,000 sq ft per merge, rooms up to about 30 by 30 ft, scans under 5 minutes and at least 50 lux,
and says multi-room capture works best on a single floor. Each floor here is its own merge.

If `StructureBuilder` fails, the plan and JSON are still written with the rooms side by side, marked `unmerged`, but
there's no USDZ.

## Files

Everything lives in `Application Support/HouseScan`:

| Path | What |
| --- | --- |
| `library.json` | Projects, floors, rooms |
| `rooms/<id>/captured-room.json` | The processed `CapturedRoom` |
| `floors/<id>/world.arworldmap` | The floor's AR world map, for lining up later visits |
| `photos/<id>.jpg` | Item and site note photos |

All of it is included in iCloud and Finder backups, if those are on.

Only the processed room is kept, not RoomPlan's raw `CapturedRoomData`. On every real scan the raw data failed to
encode with "Invalid data" and no coding path, as Apple's forums also report, so there is no way to reprocess a room
later. RoomPlan values can also hold NaN, so saved files and the export JSON write NaN and infinity as the strings
`nan`, `inf` and `-inf`.

## Exports

The USDZ uses RoomPlan's `.mesh` format, the one that cuts doors and windows out of walls and keeps polygonal walls.

The JSON (`format: house-scan-floor/1`) is in metres and degrees, in the scan's own frame: Y up, origin arbitrary, no
relation to compass north. Each surface has `size`, `position`, `rotation` (`yawDegrees` and a quaternion) and the full
`transform`, column by column.

The plan draws no door swing, because RoomPlan doesn't report one, and curved walls as straight lines. The curve data is
in the JSON.

The plan is turned so most walls run square to the page, since a scan's axes come from wherever the phone started; the
JSON keeps the scan's own frame. Room labels that would overlap are pushed apart, and a wall length that would land on
a label or another length is left off the plan. Every length is still in the JSON.

To redraw exported floors without a phone, put their JSON in a folder outside the repo and run the tests with
`TEST_RUNNER_REVIEW_PLANS=<folder>`; `testRedrawExportedFloorsForReview` writes a PNG next to each.

## Insurance items

Items belong to a room, scanned or not. The PDF inventory covers a project or one room, and lists every photo and the
total of the values entered, which it says are the owner's entries, not an appraisal.

Photos are redrawn as plain JPEGs up to 3000 px, so a library photo can't carry a GPS tag into an inventory.

Scan a Label adds an item from one photo of a rating or serial label. Vision reads the text on the phone (Apple: "all of
this happens on the device", WWDC19 session 234), with language correction off so serial numbers aren't turned into words.
The parser finds model and serial keywords on the same line, below, or in side-by-side columns, skips ratings like 120V,
and uses a Code 128, Code 39, Code 93 or Data Matrix barcode to correct look-alike characters or supply a missing serial.
The make comes from a short list of brands. Every such item keeps the label photo and is marked for checking until it's
saved in the editor, where a tap on the photo zooms it. The PDF says which items are still unchecked.

## Site notes

The site note camera reads position and heading at the moment of the shutter, which the system camera can't do. The CSV
comes with the photos, named as its `photo_file` column says. The photos themselves carry no GPS tag.

These are phone estimates, not survey data, and every label says so:

- `horizontal_accuracy_m` is Apple's "radius of uncertainty", which is the phone's own estimate of its error.
- With Precise Location off, the position is deliberately blurred and the label quotes no radius.
- `heading_accuracy_deg` is Apple's "maximum deviation". Compass readings drift near metal and indoors.
- Heading is measured from the top of the phone held in portrait, as Core Location defines it.
- A fix over 15 seconds old is called out.

## Testing

RoomPlan's types decode from JSON, so the tests build invented rooms and decode them into real `CapturedRoom` values.
Everything after the camera runs that way on the simulator, whose `StructureBuilder` returns an empty structure instead
of throwing.

Invented rooms have no real `coreModel`, RoomPlan's private data, so on a device they crash if reloaded or merged, and
those tests skip or don't apply there. `DeviceTests` exports an invented room to USD, and merges and exports whatever
real scans are saved in the app, printing only counts. Scan two rooms on one floor, then run `scripts/phone.sh test`.

Never commit real scans, exports or a real address. Test data is invented, and `.gitignore` blocks the scan file types.

## Blueprint dashboard

`blueprint/` is a web page that shows the exported floors stacked in 3D as a blueprint, with Home Assistant devices per
room. See `blueprint/README.md`.

## License

MIT. See `LICENSE`.
