import RoomPlan
import XCTest
@testable import HouseScan

/// Run on a real LiDAR iPhone, where StructureBuilder and USD export actually work. Skipped on the simulator.
/// Invented rooms can't be merged on a device (see Fixtures), so the merge test uses the scans saved in the app.
/// It prints counts only, so nothing from a real scan reaches a log.
final class DeviceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        try XCTSkipUnless(RoomCaptureSession.isSupported, "Needs a LiDAR device")
        directory = FileManager.default.temporaryDirectory.appending(path: "DeviceTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    func testRoomExportsUSDZ() throws {
        let url = directory.appending(path: "room.usdz")
        try Fixtures.room().export(to: url, exportOptions: .mesh)
        let size = try XCTUnwrap(url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
        print("DEVICE room usdz bytes", size)
        XCTAssertGreaterThan(size, 0)
    }

    @MainActor
    func testSavedScansReloadMergeAndExport() async throws {
        let store = Store()
        let floors = store.library.projects.flatMap(\.floors).filter { $0.rooms.filter { $0.scan != nil }.count >= 2 }
        try XCTSkipIf(floors.isEmpty, "Scan two rooms on one floor first")

        for floor in floors {
            func load() throws -> [RoomInput] {
                try floor.rooms.compactMap { room -> RoomInput? in
                    guard let scan = room.scan else { return nil }
                    return RoomInput(name: "Room", spaceID: scan.spaceID, scannedAt: scan.scannedAt, room: try store.files.loadCapturedRoom(room.id))
                }
            }
            let inputs = try load()
            let folder = directory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let result = try await FloorExporter.export(project: "Test", floor: "Test", inputs: inputs, to: folder)
            print("DEVICE saved floor rooms", inputs.count, "files", result.files.map(\.pathExtension).sorted(), "warnings", result.warnings.count)
            XCTAssertTrue(result.files.contains { $0.pathExtension == "usdz" })

            // The merge moves the floor, so a room name placed by the saved position lands outside the plan or in the wrong room.
            let (group, _) = try FloorExporter.splitBySpace(load())
            let structure = try await FloorExporter.merge(group.map(\.room))
            let centres = structure.walls.map(\.transform.columns.3)
            let (xs, zs) = (centres.map { Double($0.x) }, centres.map { Double($0.z) })
            let names = FloorExporter.summaries(group, merged: structure)
            let inside = names.filter { (xs.min()!...xs.max()!).contains($0.center.x) && (zs.min()!...zs.max()!).contains($0.center.z) }
            print("DEVICE room names inside the plan", inside.count, "of", names.count)
            XCTAssertEqual(inside.count, names.count)
        }
    }
}
