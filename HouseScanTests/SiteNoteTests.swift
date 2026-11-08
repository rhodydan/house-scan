import CoreLocation
import XCTest
@testable import HouseScan

final class SiteNoteTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func location(accuracy: Double, vertical: Double = 5, age: Double = 1) -> CLLocation {
        CLLocation(coordinate: CLLocationCoordinate2D(latitude: 12.345678, longitude: -65.432109), altitude: 42,
                   horizontalAccuracy: accuracy, verticalAccuracy: vertical, timestamp: now.addingTimeInterval(-age))
    }

    private func position(accuracy: Double = 8, age: Double = 1, precise: Bool = true) -> SitePosition {
        SitePosition(latitude: 12.345678, longitude: -65.432109, horizontalAccuracy: accuracy, altitude: 42,
                     verticalAccuracy: 5, fixAgeSeconds: age, isPrecise: precise)
    }

    func testInvalidFixIsDropped() {
        XCTAssertNil(SitePosition(location(accuracy: -1), at: now, isPrecise: true))
    }

    func testPositionKeepsWhatCoreLocationSaid() throws {
        let position = try XCTUnwrap(SitePosition(location(accuracy: 8, age: 3), at: now, isPrecise: true))
        XCTAssertEqual(position.horizontalAccuracy, 8)
        XCTAssertEqual(position.altitude, 42)
        XCTAssertEqual(position.fixAgeSeconds, 3, accuracy: 0.01)
    }

    func testInvalidAltitudeIsDropped() throws {
        let position = try XCTUnwrap(SitePosition(location(accuracy: 8, vertical: -1), at: now, isPrecise: true))
        XCTAssertNil(position.altitude)
        XCTAssertNil(position.verticalAccuracy)
    }

    func testInvalidHeadingIsDropped() {
        XCTAssertNil(SiteHeading(magnetic: 90, true: 100, accuracy: -1))
        XCTAssertNil(SiteHeading(magnetic: -1, true: 100, accuracy: 10))
    }

    func testTrueNorthIsOptional() throws {
        let heading = try XCTUnwrap(SiteHeading(magnetic: 90, true: -1, accuracy: 10))
        XCTAssertNil(heading.trueDegrees)
        XCTAssertTrue(SiteLabel.heading(heading).contains("(magnetic)"))
    }

    func testEveryPositionLabelDisclaimsSurveyGrade() {
        let cases: [SitePosition?] = [nil, position(accuracy: 3), position(accuracy: 12), position(accuracy: 40), position(accuracy: 500),
                                      position(precise: false), position(age: 120)]
        for position in cases {
            XCTAssertTrue(SiteLabel.position(position).contains("Not survey-grade"), SiteLabel.position(position))
        }
    }

    func testPositionLabelsGradeHonestly() {
        XCTAssertTrue(SiteLabel.position(position(accuracy: 4)).contains("within about 4 m (13 ft): good for a phone"))
        XCTAssertTrue(SiteLabel.position(position(accuracy: 12)).contains("fair"))
        XCTAssertTrue(SiteLabel.position(position(accuracy: 40)).contains("poor"))
        XCTAssertTrue(SiteLabel.position(position(accuracy: 500)).contains("very poor"))
    }

    func testImprecisePositionNeverQuotesARadius() {
        let label = SiteLabel.position(position(accuracy: 3, precise: false))
        XCTAssertTrue(label.contains("Precise Location is off"))
        XCTAssertFalse(label.contains("3 m"))
    }

    func testStaleFixIsCalledOut() {
        XCTAssertTrue(SiteLabel.position(position(age: 40)).contains("40 s old"))
        XCTAssertFalse(SiteLabel.position(position(age: 2)).contains("old"))
    }

    func testHeadingLabel() {
        let heading = SiteHeading(trueDegrees: 134.6, magneticDegrees: 120, accuracyDegrees: 15)
        XCTAssertEqual(SiteLabel.heading(heading), "135° SE (true), within about 15°. Compass readings drift near metal and indoors.")
        XCTAssertEqual(SiteLabel.heading(nil), "No compass heading.")
    }

    func testCompassPoints() {
        XCTAssertEqual(SiteLabel.compassPoint(0), "N")
        XCTAssertEqual(SiteLabel.compassPoint(359), "N")
        XCTAssertEqual(SiteLabel.compassPoint(90), "E")
        XCTAssertEqual(SiteLabel.compassPoint(225), "SW")
    }

    /// Reads RFC 4180 CSV back, independently of the writer.
    private func parse(_ csv: String) -> [[String]] {
        var rows: [[String]] = [[]], field = "", quoted = false
        var characters = Array(csv.unicodeScalars)[...]
        while let c = characters.popFirst() {
            if quoted {
                if c == "\"" {
                    if characters.first == "\"" { field.unicodeScalars.append(characters.removeFirst()) } else { quoted = false }
                } else { field.unicodeScalars.append(c) }
            } else if c == "\"" { quoted = true
            } else if c == "," { rows[rows.count - 1].append(field); field = ""
            } else if c == "\r" { continue
            } else if c == "\n" { rows[rows.count - 1].append(field); field = ""; rows.append([])
            } else { field.unicodeScalars.append(c) }
        }
        return rows.filter { !$0.isEmpty }
    }

    func testCSVRoundTripsAwkwardNotes() {
        let awkward = "North fence, by the \"big\" oak\nsecond line"
        let note = SiteNote(takenAt: now, note: awkward, photo: "x.jpg", position: position(),
                            heading: SiteHeading(trueDegrees: 134.6, magneticDegrees: 120, accuracyDegrees: 15))
        let rows = parse(SiteNotesCSV.make([note]))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0], SiteNotesCSV.header)
        let row = Dictionary(uniqueKeysWithValues: zip(rows[0], rows[1]))
        XCTAssertEqual(row["note"], awkward)
        XCTAssertEqual(row["latitude"], "12.345678")
        XCTAssertEqual(row["longitude"], "-65.432109")
        XCTAssertEqual(row["horizontal_accuracy_m"], "8.0")
        XCTAssertEqual(row["heading_true_deg"], "134.6")
        XCTAssertEqual(row["heading_accuracy_deg"], "15.0")
        XCTAssertEqual(row["precise_location"], "yes")
        XCTAssertEqual(row["photo_file"], "site-note-001.jpg")
        XCTAssertTrue(row["position_label"]?.contains("Not survey-grade") == true)
        XCTAssertEqual(row["taken_at_utc"], now.ISO8601Format())
    }

    func testCSVLeavesMissingReadingsBlank() {
        let rows = parse(SiteNotesCSV.make([SiteNote(takenAt: now, note: "", photo: "x.jpg")]))
        let row = Dictionary(uniqueKeysWithValues: zip(rows[0], rows[1]))
        XCTAssertEqual(row["latitude"], "")
        XCTAssertEqual(row["heading_true_deg"], "")
        XCTAssertEqual(row["position_label"], "No GPS position. Not survey-grade.")
    }

    func testExportWritesCSVAndNamedPhotos() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "SiteExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = ScanFiles(root: root)
        let names = try [Data([1]), Data([2])].map(files.savePhoto)
        let notes = names.map { SiteNote(takenAt: now, note: "n", photo: $0) }

        let urls = try SiteNotesCSV.export(notes, project: "Sample House", files: files, to: root.appending(path: "out"))
        XCTAssertEqual(urls.map(\.lastPathComponent), ["Sample-House-site-notes.csv", "site-note-001.jpg", "site-note-002.jpg"])
        XCTAssertEqual(try Data(contentsOf: urls[2]), Data([2]))
    }
}
