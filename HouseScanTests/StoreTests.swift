import RoomPlan
import XCTest
@testable import HouseScan

@MainActor
final class StoreTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appending(path: "StoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func scanned(_ store: Store) async throws -> (Project.ID, Floor.ID, Room.ID) {
        let project = store.addProject(name: "Sample")
        let floor = store.addFloor(name: "Main", to: project)
        let room = try await store.saveScan(Fixtures.room(), name: "Den", spaceID: UUID(), existing: nil, floor: floor, in: project)
        return (project, floor, room)
    }

    func testDefaultRootIsApplicationSupportNotDocuments() {
        XCTAssertTrue(ScanFiles.defaultRoot.path.contains("/Library/Application Support/HouseScan"))
    }

    func testTreePersistsAcrossLaunches() async throws {
        let store = Store(root: root)
        let (project, floor, room) = try await scanned(store)
        store.addFloor(name: "Upstairs", to: project)
        store.renameRoom(room, floor: floor, in: project, to: "Family Room")

        let reopened = Store(root: root)
        XCTAssertEqual(reopened.library, store.library)
        XCTAssertEqual(reopened.project(project)?.floors.map(\.name), ["Main", "Upstairs"])
        XCTAssertEqual(reopened.room(room, floor: floor, in: project)?.name, "Family Room")
    }

    func testSavedScanReopensAsARealCapturedRoom() async throws {
        try XCTSkipIf(RoomCaptureSession.isSupported, Fixtures.cannotReload)
        let store = Store(root: root)
        let (_, _, room) = try await scanned(store)
        let reopened = try Store(root: root).files.loadCapturedRoom(room)
        XCTAssertEqual(reopened.walls.count, 4)
        XCTAssertEqual(reopened.doors.count, 1)
        XCTAssertEqual(reopened.objects.first?.category, .sofa)
        XCTAssertEqual(reopened.walls.first?.dimensions.x, 5)
    }

    func testRescanKeepsTheRoomAndReplacesItsScan() async throws {
        try XCTSkipIf(RoomCaptureSession.isSupported, Fixtures.cannotReload)
        let store = Store(root: root)
        let (project, floor, room) = try await scanned(store)
        let space = UUID()
        try await store.saveScan(Fixtures.room(width: 7), name: "Den", spaceID: space, existing: room, floor: floor, in: project)
        XCTAssertEqual(store.floor(floor, in: project)?.rooms.count, 1)
        XCTAssertEqual(store.room(room, floor: floor, in: project)?.scan?.spaceID, space)
        XCTAssertEqual(try store.files.loadCapturedRoom(room).walls.first?.dimensions.x, 7)
    }

    func testDeletingRemovesFiles() async throws {
        let store = Store(root: root)
        let (project, floor, room) = try await scanned(store)
        try await store.saveWorldMap(Data([1, 2, 3]), spaceID: UUID(), floor: floor, in: project)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.files.capturedRoomFile(room).path))

        store.deleteProject(project)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.files.capturedRoomFile(room).path))
        XCTAssertFalse(store.files.hasWorldMap(floor))
        XCTAssertTrue(store.library.projects.isEmpty)
    }

    func testWorldMapRecordsTheFloorsSpace() async throws {
        let store = Store(root: root)
        let (project, floor, _) = try await scanned(store)
        XCTAssertNil(store.floor(floor, in: project)?.spaceID)
        let space = UUID()
        try await store.saveWorldMap(Data([1]), spaceID: space, floor: floor, in: project)
        XCTAssertEqual(store.floor(floor, in: project)?.spaceID, space)
        XCTAssertTrue(store.files.hasWorldMap(floor))
    }

    func testUnreadableLibraryIsNeverOverwritten() throws {
        let files = ScanFiles(root: root)
        let garbage = Data("not json".utf8)
        try files.write(garbage, to: files.libraryFile)

        let store = Store(root: root)
        XCTAssertNotNil(store.loadProblem)
        store.addProject(name: "Would overwrite")
        XCTAssertEqual(try Data(contentsOf: files.libraryFile), garbage)
    }

    func testALibraryFromBeforeItemsAndSiteNotesStillLoads() throws {
        let files = ScanFiles(root: root)
        let older = """
        {"projects":[{"id":"\(UUID().uuidString)","name":"Older","createdAt":800000000,
        "floors":[{"id":"\(UUID().uuidString)","name":"Main","rooms":[{"id":"\(UUID().uuidString)","name":"Den"}]}]}]}
        """
        try files.write(Data(older.utf8), to: files.libraryFile)
        let store = Store(root: root)
        XCTAssertNil(store.loadProblem)
        XCTAssertEqual(store.library.projects.first?.floors.first?.rooms.first?.items, [])
        XCTAssertEqual(store.library.projects.first?.siteNotes, [])
    }

    func testItemsSaveAndReplacedPhotosAreDeleted() async throws {
        let store = Store(root: root)
        let (project, floor, room) = try await scanned(store)
        let first = try store.files.savePhoto(Data([1]))
        let second = try store.files.savePhoto(Data([2]))
        var item = InventoryItem(name: "Lamp", serialNumber: "S1", valueCents: 2500, photos: [first, second])
        store.saveItem(item, room: room, floor: floor, in: project)

        item.photos = [second]
        item.valueCents = 3000
        store.saveItem(item, room: room, floor: floor, in: project)

        let reopened = Store(root: root)
        XCTAssertEqual(reopened.room(room, floor: floor, in: project)?.items, [item])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.files.photoFile(first).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.files.photoFile(second).path))
    }

    func testDeletingARoomDeletesItsItemPhotos() async throws {
        let store = Store(root: root)
        let (project, floor, room) = try await scanned(store)
        let photo = try store.files.savePhoto(Data([1]))
        store.saveItem(InventoryItem(name: "Lamp", photos: [photo]), room: room, floor: floor, in: project)
        store.deleteRoom(room, floor: floor, in: project)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.files.photoFile(photo).path))
    }

    func testSiteNotesPersistAndDeletingTheProjectDeletesTheirPhotos() throws {
        let store = Store(root: root)
        let project = store.addProject(name: "Sample")
        let photo = try store.files.savePhoto(Data([1]))
        let note = SiteNote(takenAt: Date(), note: "Gate", photo: photo)
        store.addSiteNote(note, to: project)
        store.updateSiteNote(note.id, text: "Back gate", in: project)
        XCTAssertEqual(Store(root: root).project(project)?.siteNotes.first?.note, "Back gate")

        store.deleteProject(project)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.files.photoFile(photo).path))
    }

    func testSavedFilesAreIncludedInBackups() async throws {
        let store = Store(root: root)
        let (project, floor, _) = try await scanned(store)
        try await store.saveWorldMap(Data([1]), spaceID: UUID(), floor: floor, in: project)
        _ = try store.files.savePhoto(Data([1]))

        let urls = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isExcludedFromBackupKey]))
        var count = 0
        for case let url as URL in urls {
            count += 1
            XCTAssertEqual(try url.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, false, url.lastPathComponent)
        }
        XCTAssertGreaterThan(count, 4)
    }
}
