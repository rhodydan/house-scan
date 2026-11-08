import Foundation
import Observation
import RoomPlan

/// The app's single source of truth. Every change saves library.json straight away.
@MainActor @Observable
final class Store {
    private(set) var library = Library()
    /// Set when library.json exists but can't be read. Saving is then refused, so a bad read can't wipe the real file.
    private(set) var loadProblem: String?
    var saveProblem: String?
    let files: ScanFiles

    init(root: URL = ScanFiles.defaultRoot) {
        files = ScanFiles(root: root)
        load()
    }

    private func load() {
        do {
            guard FileManager.default.fileExists(atPath: files.libraryFile.path) else { return }
            library = try JSONDecoder().decode(Library.self, from: Data(contentsOf: files.libraryFile))
        } catch {
            loadProblem = "House Scan couldn't read its saved data, so changes won't be saved. (\(error.localizedDescription))"
        }
    }

    private func mutate(_ change: (inout Library) -> Void) {
        guard loadProblem == nil else { return }
        change(&library)
        do {
            try files.write(Self.encoder.encode(library), to: files.libraryFile)
        } catch {
            saveProblem = "Couldn't save: \(error.localizedDescription)"
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    // MARK: Lookups

    func project(_ id: Project.ID) -> Project? { library.projects.first { $0.id == id } }

    func floor(_ id: Floor.ID, in projectID: Project.ID) -> Floor? {
        project(projectID)?.floors.first { $0.id == id }
    }

    func room(_ id: Room.ID, floor floorID: Floor.ID, in projectID: Project.ID) -> Room? {
        floor(floorID, in: projectID)?.rooms.first { $0.id == id }
    }

    private func editProject(_ id: Project.ID, _ change: (inout Project) -> Void) {
        mutate { library in
            guard let index = library.projects.firstIndex(where: { $0.id == id }) else { return }
            change(&library.projects[index])
        }
    }

    private func editFloor(_ id: Floor.ID, in projectID: Project.ID, _ change: (inout Floor) -> Void) {
        editProject(projectID) { project in
            guard let index = project.floors.firstIndex(where: { $0.id == id }) else { return }
            change(&project.floors[index])
        }
    }

    private func editRoom(_ id: Room.ID, floor floorID: Floor.ID, in projectID: Project.ID, _ change: (inout Room) -> Void) {
        editFloor(floorID, in: projectID) { floor in
            guard let index = floor.rooms.firstIndex(where: { $0.id == id }) else { return }
            change(&floor.rooms[index])
        }
    }

    // MARK: Projects, floors, rooms

    @discardableResult
    func addProject(name: String) -> Project.ID {
        let project = Project(name: name)
        mutate { $0.projects.append(project) }
        return project.id
    }

    func renameProject(_ id: Project.ID, to name: String) {
        editProject(id) { $0.name = name }
    }

    func deleteProject(_ id: Project.ID) {
        project(id)?.floors.forEach(removeFiles)
        project(id)?.siteNotes.forEach { removePhotos([$0.photo]) }
        mutate { $0.projects.removeAll { $0.id == id } }
    }

    @discardableResult
    func addFloor(name: String, to projectID: Project.ID) -> Floor.ID {
        let floor = Floor(name: name)
        editProject(projectID) { $0.floors.append(floor) }
        return floor.id
    }

    func renameFloor(_ id: Floor.ID, in projectID: Project.ID, to name: String) {
        editFloor(id, in: projectID) { $0.name = name }
    }

    func deleteFloor(_ id: Floor.ID, in projectID: Project.ID) {
        if let floor = floor(id, in: projectID) { removeFiles(of: floor) }
        editProject(projectID) { $0.floors.removeAll { $0.id == id } }
    }

    private func removeFiles(of floor: Floor) {
        floor.rooms.forEach(removeFiles)
        files.remove(files.floorDirectory(floor.id))
    }

    private func removeFiles(of room: Room) {
        files.remove(files.roomDirectory(room.id))
        room.items.forEach { removePhotos($0.photos) }
    }

    func removePhotos(_ names: [String]) {
        names.forEach { files.remove(files.photoFile($0)) }
    }

    @discardableResult
    func addRoom(name: String, floor floorID: Floor.ID, in projectID: Project.ID) -> Room.ID {
        let room = Room(name: name)
        editFloor(floorID, in: projectID) { $0.rooms.append(room) }
        return room.id
    }

    func renameRoom(_ id: Room.ID, floor floorID: Floor.ID, in projectID: Project.ID, to name: String) {
        editRoom(id, floor: floorID, in: projectID) { $0.name = name }
    }

    func deleteRoom(_ id: Room.ID, floor floorID: Floor.ID, in projectID: Project.ID) {
        if let room = room(id, floor: floorID, in: projectID) { removeFiles(of: room) }
        editFloor(floorID, in: projectID) { $0.rooms.removeAll { $0.id == id } }
    }

    // MARK: Insurance items

    /// Adds the item, or replaces the one with the same ID. Photos it no longer uses are deleted.
    func saveItem(_ item: InventoryItem, room roomID: Room.ID, floor floorID: Floor.ID, in projectID: Project.ID) {
        let previous = room(roomID, floor: floorID, in: projectID)?.items.first { $0.id == item.id }
        removePhotos(previous?.photos.filter { !item.photos.contains($0) } ?? [])
        editRoom(roomID, floor: floorID, in: projectID) { room in
            if let index = room.items.firstIndex(where: { $0.id == item.id }) {
                room.items[index] = item
            } else {
                room.items.append(item)
            }
        }
    }

    func deleteItem(_ item: InventoryItem, room roomID: Room.ID, floor floorID: Floor.ID, in projectID: Project.ID) {
        removePhotos(item.photos)
        editRoom(roomID, floor: floorID, in: projectID) { $0.items.removeAll { $0.id == item.id } }
    }

    // MARK: Site notes

    func addSiteNote(_ note: SiteNote, to projectID: Project.ID) {
        editProject(projectID) { $0.siteNotes.append(note) }
    }

    func updateSiteNote(_ id: SiteNote.ID, text: String, in projectID: Project.ID) {
        editProject(projectID) { project in
            guard let index = project.siteNotes.firstIndex(where: { $0.id == id }) else { return }
            project.siteNotes[index].note = text
        }
    }

    func deleteSiteNote(_ note: SiteNote, in projectID: Project.ID) {
        removePhotos([note.photo])
        editProject(projectID) { $0.siteNotes.removeAll { $0.id == note.id } }
    }

    // MARK: Scans

    /// Saves a finished scan, into `existing` when rescanning or a new room otherwise, and returns the room.
    @discardableResult
    func saveScan(_ captured: CapturedRoom, name: String, spaceID: UUID, existing: Room.ID?,
                  floor floorID: Floor.ID, in projectID: Project.ID) async throws -> Room.ID {
        let roomID = existing ?? UUID()
        let files = files
        try await Task.detached { try files.saveScan(captured, id: roomID) }.value
        let record = ScanRecord(scannedAt: Date(), spaceID: spaceID)
        if existing != nil {
            editRoom(roomID, floor: floorID, in: projectID) {
                $0.name = name
                $0.scan = record
            }
        } else {
            editFloor(floorID, in: projectID) { $0.rooms.append(Room(id: roomID, name: name, scan: record)) }
        }
        return roomID
    }

    func saveWorldMap(_ data: Data, spaceID: UUID, floor floorID: Floor.ID, in projectID: Project.ID) async throws {
        let files = files
        try await Task.detached { try files.write(data, to: files.worldMapFile(floorID)) }.value
        editFloor(floorID, in: projectID) { $0.spaceID = spaceID }
    }
}
