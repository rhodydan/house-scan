import Foundation
import Observation
import RoomPlan

/// The scan screen's state, kept apart from the camera so the rules can be read in one place.
@MainActor @Observable
final class ScanModel {
    enum Phase: Equatable {
        case starting
        case relocalizing(String)
        case ready
        case scanning
        case processing
        case review
        case saving
        case saved
        /// iOS took the camera away, so the coordinate space can't be trusted any more.
        case interrupted
        case failed(String)
    }

    private(set) var phase = Phase.starting
    var roomName = ""
    private(set) var roomsSaved = 0
    private(set) var worldMapProblem: String?
    /// Rooms already on this floor that a new space can't merge with.
    private(set) var unalignedWarning: String?

    private let store: Store
    private let projectID: Project.ID
    private let floorID: Floor.ID
    private var replacing: Room.ID?
    private var spaceID = UUID()
    private var pending: CapturedRoom?
    private var cameraLost = false
    private weak var camera: ScanViewController?

    init(store: Store, projectID: Project.ID, floorID: Floor.ID, replacing: Room.ID?) {
        self.store = store
        self.projectID = projectID
        self.floorID = floorID
        self.replacing = replacing
    }

    var floorName: String { store.floor(floorID, in: projectID)?.name ?? "" }

    func attach(_ camera: ScanViewController) {
        self.camera = camera
        camera.onEvent = { [weak self] event in self?.handle(event) }
        if let floor = store.floor(floorID, in: projectID), let saved = floor.spaceID, store.files.hasWorldMap(floorID) {
            do {
                let data = try Data(contentsOf: store.files.worldMapFile(floorID))
                try camera.relocalize(with: data)
                spaceID = saved
                phase = .relocalizing("Starting the camera…")
            } catch {
                phase = .failed("This floor's saved map couldn't be read: \(error.localizedDescription)")
            }
        } else {
            camera.prepareNewSpace()
            noteUnalignedRooms()
            phase = .ready
        }
    }

    private func noteUnalignedRooms() {
        let earlier = store.floor(floorID, in: projectID)?.rooms.filter { $0.scan != nil && $0.id != replacing }.count ?? 0
        if earlier > 0 {
            unalignedWarning = "New rooms won't line up with the \(earlier) already on this floor, so they won't merge with them."
        }
    }

    private func handle(_ event: ScanViewController.Event) {
        switch event {
        case .relocalizationProgress(let message):
            phase = .relocalizing(message)
        case .relocalized:
            phase = .ready
        case .roomReady(let room):
            pending = room
            roomName = replacingName ?? suggestedName(for: room)
            phase = .review
        case .failed(let message):
            phase = .failed(message)
        }
    }

    private var replacingName: String? {
        replacing.flatMap { store.room($0, floor: floorID, in: projectID)?.name }
    }

    private func suggestedName(for room: CapturedRoom) -> String {
        let label = room.sections.map(\.label).first { $0 != .unidentified }
        switch label {
        case .livingRoom: return "Living Room"
        case .bedroom: return "Bedroom"
        case .bathroom: return "Bathroom"
        case .kitchen: return "Kitchen"
        case .diningRoom: return "Dining Room"
        default:
            let count = store.floor(floorID, in: projectID)?.rooms.count ?? 0
            return "Room \(count + 1)"
        }
    }

    // MARK: Actions

    func skipRelocalization() {
        spaceID = UUID()
        camera?.abandonRelocalization()
        noteUnalignedRooms()
        phase = .ready
    }

    func startRoom() {
        camera?.startRoom()
        phase = .scanning
    }

    func finishRoom() {
        camera?.finishRoom()
        phase = .processing
    }

    func discardRoom() {
        pending = nil
        phase = cameraLost ? .interrupted : .ready
    }

    func saveRoom() async {
        guard let pending else { return }
        phase = .saving
        let name = roomName.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await store.saveScan(pending, name: name.isEmpty ? "Room" : name, spaceID: spaceID,
                                     existing: replacing, floor: floorID, in: projectID)
        } catch {
            phase = .failed("The scan couldn't be saved: \(error.localizedDescription)")
            return
        }
        self.pending = nil
        replacing = nil
        roomsSaved += 1
        await saveWorldMap()
        phase = cameraLost ? .interrupted : .saved
    }

    /// The map is what lets a later visit line up with these rooms. Losing it costs only that, so the room stays saved.
    private func saveWorldMap() async {
        guard !cameraLost, let camera else { return }
        do {
            let data = try await camera.archivedWorldMap()
            try await store.saveWorldMap(data, spaceID: spaceID, floor: floorID, in: projectID)
            worldMapProblem = nil
        } catch {
            worldMapProblem = "This floor's map couldn't be saved (\(error.localizedDescription)). Scan any other rooms now: after you leave, new rooms won't line up with this one."
        }
    }

    /// The app went to the background. iOS stops the camera, and the session's coordinates can't be relied on after.
    /// A finished room awaiting review is still good, so it can be saved. A scan in progress is lost.
    func appWentToBackground() {
        cameraLost = true
        switch phase {
        case .review, .saving, .failed: break
        default: phase = .interrupted
        }
    }

    func close() {
        camera?.stopEverything()
    }
}
