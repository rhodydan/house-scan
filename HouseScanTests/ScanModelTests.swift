import XCTest
@testable import HouseScan

/// The scan screen's rules that don't need a camera.
@MainActor
final class ScanModelTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ScanModelTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testBackgroundDuringAScanInterruptsIt() {
        let store = Store(root: root)
        let project = store.addProject(name: "Sample")
        let floor = store.addFloor(name: "Main", to: project)
        let model = ScanModel(store: store, projectID: project, floorID: floor, replacing: nil)
        model.startRoom()
        XCTAssertEqual(model.phase, .scanning)
        model.appWentToBackground()
        XCTAssertEqual(model.phase, .interrupted)
    }
}
