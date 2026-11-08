import PDFKit
import RoomPlan
import XCTest
@testable import HouseScan

final class ExportTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appending(path: "ExportTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func file(_ result: FloorExportResult, _ suffix: String) -> URL? {
        result.files.first { $0.lastPathComponent.hasSuffix(suffix) }
    }

    private func document(_ result: FloorExportResult) throws -> FloorDocument {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(FloorDocument.self, from: Data(contentsOf: XCTUnwrap(file(result, ".json"))))
    }

    func testRenderSamplePlanForReview() throws {
        var document = try FloorDocument.fixture()
        let second = try Fixtures.room(x: 5, z: 0, width: 3.2, depth: 4)
        let source = GeometrySource(second)
        document.walls += source.walls.map(PlanSurface.init)
        document.doors += source.doors.map(PlanSurface.init)
        document.windows += source.windows.map(PlanSurface.init)
        document.objects += source.objects.map(PlanObject.init)
        document.rooms.append(RoomSummary(name: "Kitchen", room: second))
        let out = FileManager.default.temporaryDirectory
        try PlanRenderer.png(document).write(to: out.appending(path: "sample-plan.png"))
        try PlanRenderer.pdf(document).write(to: out.appending(path: "sample-plan.pdf"))
        print("SAMPLE_PLAN_DIR \(out.path)")
    }

    func testPlanIsNotMirrored() throws {
        let area = CGRect(x: 0, y: 0, width: 500, height: 400)
        let layout = try XCTUnwrap(PlanLayout(FloorDocument.fixture(), area: area))
        let origin = layout.point(PlanPoint(x: 0, z: 0))
        XCTAssertGreaterThan(layout.point(PlanPoint(x: 1, z: 0)).x, origin.x, "+X should be to the right")
        XCTAssertGreaterThan(layout.point(PlanPoint(x: 0, z: 1)).y, origin.y, "+Z should be down the page")
    }

    /// Turns every wall, opening and object of a document about the origin, as a scan started at a slant would.
    private func turned(_ document: FloorDocument, by angle: Double) -> FloorDocument {
        func turn(_ transform: [Double], _ position: inout Vector3) -> [Double] {
            var t = transform
            for column in [0, 8, 12] {
                let p = PlanPoint(x: t[column], z: t[column + 2]).turned(by: angle)
                (t[column], t[column + 2]) = (p.x, p.z)
            }
            position = Vector3(x: t[12], y: position.y, z: t[14])
            return t
        }
        var document = document
        for path in [\FloorDocument.walls, \.doors, \.windows, \.openings] {
            document[keyPath: path] = document[keyPath: path].map { var s = $0; s.transform = turn(s.transform, &s.position); return s }
        }
        document.objects = document.objects.map { var o = $0; o.transform = turn(o.transform, &o.position); return o }
        return document
    }

    func testASlantedScanPrintsSquare() throws {
        let document = turned(try FloorDocument.fixture(), by: 20 * .pi / 180)
        XCTAssertEqual(document.mainWallDirection * 180 / .pi, 20, accuracy: 0.01)
        let layout = try XCTUnwrap(PlanLayout(document, area: CGRect(x: 0, y: 0, width: 500, height: 400)))
        for wall in document.walls {
            let (a, b) = (layout.point(wall.ends.0), layout.point(wall.ends.1))
            XCTAssertLessThan(min(abs(a.x - b.x), abs(a.y - b.y)), 0.01, "every wall should run straight across or down the page")
        }
    }

    func testAnUnslantedScanIsntTurned() throws {
        XCTAssertEqual(try FloorDocument.fixture().mainWallDirection, 0, accuracy: 0.0001)
    }

    func testRoomLabelsDontOverlap() throws {
        var document = try FloorDocument.fixture()
        let first = document.rooms[0]
        for (index, name) in ["Butler", "Pantry", "Closet"].enumerated() {
            var room = first
            room.name = name
            room.center.x += 0.2 * Double(index + 1)
            document.rooms.append(room)
        }
        let layout = try XCTUnwrap(PlanLayout(document, area: CGRect(x: 0, y: 0, width: 500, height: 400)))
        let frames = PlanRenderer.roomLabels(document, layout).map(\.frame)
        for i in frames.indices {
            for j in frames.indices where j > i {
                XCTAssertFalse(frames[i].intersects(frames[j]), "labels \(i) and \(j) overlap")
            }
        }
    }

    /// Redraws real exported floors for a look by eye. Set TEST_RUNNER_REVIEW_PLANS to a folder of exported JSON outside
    /// the repo; the PNGs are written next to them. Skipped otherwise, so no real scan is needed to run the suite.
    func testRedrawExportedFloorsForReview() throws {
        let path = ProcessInfo.processInfo.environment["REVIEW_PLANS"]
        try XCTSkipIf(path == nil, "Set TEST_RUNNER_REVIEW_PLANS to redraw exported floors.")
        let folder = URL(filePath: path ?? "", directoryHint: .isDirectory)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        for file in try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) where file.pathExtension == "json" {
            let document = try decoder.decode(FloorDocument.self, from: Data(contentsOf: file))
            try PlanRenderer.png(document).write(to: file.deletingPathExtension().appendingPathExtension("redrawn.png"))
        }
    }

    func testPlanFitsItsArea() throws {
        let area = CGRect(x: 40, y: 60, width: 500, height: 300)
        let document = try FloorDocument.fixture()
        let layout = try XCTUnwrap(PlanLayout(document, area: area))
        for wall in document.walls {
            for end in [wall.ends.0, wall.ends.1] {
                XCTAssertTrue(area.insetBy(dx: -0.01, dy: -0.01).contains(layout.point(end)))
            }
        }
    }

    func testPlanWithNoWallsThrows() throws {
        var document = try FloorDocument.fixture()
        document.walls = []
        XCTAssertThrowsError(try PlanRenderer.pdf(document))
        XCTAssertThrowsError(try PlanRenderer.png(document))
    }

    func testPNGShowsWallsWhereTheyShouldBe() throws {
        let document = try FloorDocument.fixture()
        let data = try PlanRenderer.png(document)
        let image = try XCTUnwrap(UIImage(data: data)?.cgImage)
        let page = PlanRenderer.pageSize(for: document)
        XCTAssertEqual(image.width, Int(page.width * 4))
        XCTAssertEqual(image.height, Int(page.height * 4))

        // Read pixels through a known format.
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try XCTUnwrap(CGContext(data: &pixels, width: image.width, height: image.height, bitsPerComponent: 8,
                                              bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        func brightness(_ point: CGPoint) -> Int {
            let index = (Int(point.y * 4) * image.width + Int(point.x * 4)) * 4
            return (Int(pixels[index]) + Int(pixels[index + 1]) + Int(pixels[index + 2])) / 3
        }

        let area = CGRect(x: 62, y: 76, width: page.width - 124, height: page.height - 168)
        let layout = try XCTUnwrap(PlanLayout(document, area: area))
        // West wall, away from labels and gaps: dark. Inside the room, near no label: white.
        XCTAssertLessThan(brightness(layout.point(PlanPoint(x: 0, z: 1))), 80)
        XCTAssertGreaterThan(brightness(layout.point(PlanPoint(x: 1, z: 1))), 240)
        // The north wall is cleared where its window sits, so it isn't solid wall colour at the window's edge line.
        let throughWindow = layout.point(PlanPoint(x: 2.5, z: 0))
        XCTAssertGreaterThan(brightness(throughWindow), 200)
    }

    func testPDFIsOnePageWithTheRoomText() throws {
        let data = try PlanRenderer.pdf(FloorDocument.fixture(project: "Sample House", floor: "Main Floor"))
        let pdf = try XCTUnwrap(PDFDocument(data: data))
        XCTAssertEqual(pdf.pageCount, 1)
        let text = try XCTUnwrap(pdf.page(at: 0)?.string)
        XCTAssertTrue(text.contains("Sample House - Main Floor"), text)
        XCTAssertTrue(text.contains("Living Room"), text)
        XCTAssertTrue(text.contains("16' 5\""), "5 m wall length should print in feet: \(text)")
        XCTAssertTrue(text.contains("215 sq ft"), text)
    }

    func testRoomNamesFollowTheRoomWhenTheMergeMovesTheFloor() throws {
        var json = Fixtures.roomJSON(x: 0, z: 0, width: 5, depth: 4)
        let saved = try Fixtures.decode(CapturedRoom.self, json)
        json["identifier"] = UUID().uuidString
        json["walls"] = (json["walls"] as? [[String: Any]])?.map { wall in
            var wall = wall
            var transform = wall["transform"] as? [Float] ?? []
            transform[12] += 10
            transform[14] -= 3
            wall["transform"] = transform
            return wall
        }
        let structure = try Fixtures.structure(rooms: [json])
        let input = RoomInput(name: "Den", spaceID: UUID(), scannedAt: Date(), room: saved)

        let unmoved = try XCTUnwrap(FloorExporter.summaries([input], merged: nil).first)
        let moved = try XCTUnwrap(FloorExporter.summaries([input], merged: structure).first)
        XCTAssertEqual(moved.center.x, unmoved.center.x + 10, accuracy: 0.01)
        XCTAssertEqual(moved.center.z, unmoved.center.z - 3, accuracy: 0.01)
    }

    func testNaNFromRoomPlanDoesNotStopTheExport() throws {
        var document = try FloorDocument.fixture()
        document.openings[0].size.width = .nan
        let json = try XCTUnwrap(String(data: FloorExporter.encode(document), encoding: .utf8))
        XCTAssertTrue(json.contains("\"nan\""))
        XCTAssertEqual(Measure.feetAndInches(.nan), "unknown")
        XCTAssertEqual(Measure.squareFeet(.infinity), "unknown area")
    }

    func testJSONHasEveryWallDoorWindowAndOpening() throws {
        let data = try FloorExporter.encode(FloorDocument.fixture())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, count) in [("walls", 4), ("doors", 1), ("windows", 1), ("openings", 1)] {
            let items = try XCTUnwrap(json[key] as? [[String: Any]], key)
            XCTAssertEqual(items.count, count, key)
            for item in items {
                let size = try XCTUnwrap(item["size"] as? [String: Double])
                XCTAssertEqual(Set(size.keys), ["width", "height", "depth"])
                let position = try XCTUnwrap(item["position"] as? [String: Double])
                XCTAssertEqual(Set(position.keys), ["x", "y", "z"])
                let rotation = try XCTUnwrap(item["rotation"] as? [String: Any])
                XCTAssertNotNil(rotation["yawDegrees"])
                XCTAssertNotNil(rotation["quaternion"])
            }
        }
    }

    func testJSONNumbersAreClean() throws {
        let text = try XCTUnwrap(String(data: FloorExporter.encode(FloorDocument.fixture()), encoding: .utf8))
        XCTAssertNil(text.range(of: #"\d\.\d{6,}"#, options: .regularExpression), "Float noise leaked into the JSON")
    }

    func testSingleRoomExportsWithoutMerging() async throws {
        let merge: FloorExporter.Merge = { _ in XCTFail("One room needs no merge"); throw CocoaError(.featureUnsupported) }
        let result = try await FloorExporter.export(project: "Sample", floor: "Main", inputs: [Fixtures.input("Den", space: UUID())], to: directory, merge: merge)
        XCTAssertNotNil(file(result, "-plan.pdf"))
        XCTAssertNotNil(file(result, "-plan.png"))
        XCTAssertNotNil(file(result, ".json"))
        XCTAssertEqual(try document(result).mergeStatus, .singleRoom)
    }

    func testMergedRoomsUseTheStructure() async throws {
        let space = UUID()
        let inputs = [try Fixtures.input("Kitchen", space: space), try Fixtures.input("Den", space: space, x: 5)]
        let structure = try Fixtures.structure(rooms: [Fixtures.roomJSON(x: 0, z: 0, width: 5, depth: 4)])
        let result = try await FloorExporter.export(project: "Sample", floor: "Main", inputs: inputs, to: directory) { rooms in
            XCTAssertEqual(rooms.count, 2)
            return structure
        }
        let document = try document(result)
        XCTAssertEqual(document.mergeStatus, .merged)
        XCTAssertEqual(document.walls.count, 4, "Geometry should come from the structure, not the rooms")
        XCTAssertEqual(document.rooms.map(\.name), ["Kitchen", "Den"])
    }

    func testFailedMergeStillExportsThePlanAndSaysSo() async throws {
        let space = UUID()
        let inputs = [try Fixtures.input("Kitchen", space: space), try Fixtures.input("Den", space: space, x: 5)]
        let result = try await FloorExporter.export(project: "Sample", floor: "Main", inputs: inputs, to: directory) { _ in
            throw StructureBuilder.BuildError.invalidRoomLocation
        }
        let document = try document(result)
        XCTAssertEqual(document.mergeStatus, .unmerged)
        XCTAssertEqual(document.walls.count, 8)
        XCTAssertNil(file(result, ".usdz"))
        XCTAssertNotNil(file(result, "-plan.pdf"))
        XCTAssertTrue(result.warnings.contains { $0.contains("couldn't be merged") })
        XCTAssertEqual(document.warnings, result.warnings)
    }

    func testEmptyMergeCountsAsFailed() async throws {
        let space = UUID()
        let inputs = [try Fixtures.input("Kitchen", space: space), try Fixtures.input("Den", space: space, x: 5)]
        let empty = try Fixtures.structure(rooms: [])
        let result = try await FloorExporter.export(project: "Sample", floor: "Main", inputs: inputs, to: directory) { _ in empty }
        XCTAssertEqual(try document(result).mergeStatus, .unmerged)
        XCTAssertEqual(try document(result).walls.count, 8)
    }

    func testRoomsFromAnotherSpaceAreLeftOutAndNamed() async throws {
        let main = UUID()
        let inputs = [try Fixtures.input("Kitchen", space: main), try Fixtures.input("Den", space: main, x: 5), try Fixtures.input("Shed", space: UUID(), x: 50)]
        let structure = try Fixtures.structure(rooms: [Fixtures.roomJSON(x: 0, z: 0, width: 5, depth: 4)])
        let result = try await FloorExporter.export(project: "Sample", floor: "Main", inputs: inputs, to: directory) { rooms in
            XCTAssertEqual(rooms.count, 2)
            return structure
        }
        let document = try document(result)
        XCTAssertEqual(document.unmergedRooms, ["Shed"])
        XCTAssertTrue(result.warnings.contains { $0.contains("Shed") })
    }

    func testSpaceTieGoesToTheLatestScan() throws {
        let old = try Fixtures.input("Old", space: UUID(), date: Date(timeIntervalSince1970: 1000))
        let new = try Fixtures.input("New", space: UUID(), date: Date(timeIntervalSince1970: 2000))
        let (group, leftOut) = try FloorExporter.splitBySpace([old, new])
        XCTAssertEqual(group.map(\.name), ["New"])
        XCTAssertEqual(leftOut.map(\.name), ["Old"])
    }

    func testNoScansThrows() {
        XCTAssertThrowsError(try FloorExporter.splitBySpace([]))
    }

    func testOversizedFloorWarns() async throws {
        let result = try await FloorExporter.export(project: "Sample", floor: "Main", inputs: [Fixtures.input("Hall", space: UUID(), width: 20, depth: 10)], to: directory)
        XCTAssertTrue(result.warnings.contains { $0.contains("2,000 sq ft") })
    }

    func testFileNames() {
        XCTAssertEqual(FloorExporter.fileName("Home First Floor"), "Home-First-Floor")
        XCTAssertEqual(FloorExporter.fileName("a/b:c  d"), "a-b-c-d")
        XCTAssertEqual(FloorExporter.fileName("///"), "export")
    }
}
