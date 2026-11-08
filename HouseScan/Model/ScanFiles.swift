import ARKit
import Foundation
import RoomPlan

/// Where everything lives on disk, and the file reads and writes that don't touch the library.
///
/// All of it sits in Application Support, which iOS includes in the phone's normal backups.
struct ScanFiles: Sendable {
    let root: URL

    static var defaultRoot: URL {
        #if DEBUG
        // UI tests point the app at a folder of invented data.
        if let path = ProcessInfo.processInfo.environment["HOUSE_SCAN_ROOT"] {
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        #endif
        return URL.applicationSupportDirectory.appending(path: "HouseScan", directoryHint: .isDirectory)
    }

    var libraryFile: URL { root.appending(path: "library.json") }
    func roomDirectory(_ id: UUID) -> URL { root.appending(path: "rooms/\(id.uuidString)", directoryHint: .isDirectory) }
    func capturedRoomFile(_ id: UUID) -> URL { roomDirectory(id).appending(path: "captured-room.json") }
    func floorDirectory(_ id: UUID) -> URL { root.appending(path: "floors/\(id.uuidString)", directoryHint: .isDirectory) }
    func worldMapFile(_ floorID: UUID) -> URL { floorDirectory(floorID).appending(path: "world.arworldmap") }

    func photoFile(_ name: String) -> URL { root.appending(path: "photos/\(name)") }

    /// Saves a prepared JPEG under a new name and returns the name.
    func savePhoto(_ jpeg: Data) throws -> String {
        let name = "\(UUID().uuidString).jpg"
        try write(jpeg, to: photoFile(name))
        return name
    }

    func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    func remove(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    /// RoomPlan's values can include NaN or infinity, which JSON can't hold as numbers, so they're written as strings.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        return decoder
    }

    /// Only the processed room is kept. RoomPlan's raw `CapturedRoomData` failed to encode on every real scan, with
    /// "Invalid data" and no coding path, so there is nothing to reprocess later.
    func saveScan(_ room: CapturedRoom, id: UUID) throws {
        try write(Self.encoder.encode(room), to: capturedRoomFile(id))
    }

    func loadCapturedRoom(_ id: UUID) throws -> CapturedRoom {
        try Self.decoder.decode(CapturedRoom.self, from: Data(contentsOf: capturedRoomFile(id)))
    }

    func hasWorldMap(_ floorID: UUID) -> Bool {
        FileManager.default.fileExists(atPath: worldMapFile(floorID).path)
    }
}
