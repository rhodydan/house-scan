import Foundation
import RoomPlan

/// One scanned room going into a floor export.
struct RoomInput: Sendable {
    var name: String
    var spaceID: UUID
    var scannedAt: Date
    var room: CapturedRoom
}

struct FloorExportResult: Sendable {
    var files: [URL]
    var warnings: [String]
    var planImage: Data?
}

/// Merges a floor's rooms and writes the USDZ, PDF, PNG and JSON.
enum FloorExporter {
    typealias Merge = @Sendable ([CapturedRoom]) async throws -> CapturedStructure

    enum ExportError: LocalizedError {
        case noScans
        case emptyMerge

        var errorDescription: String? {
            switch self {
            case .noScans: "This floor has no scanned rooms yet."
            case .emptyMerge: "The merge came back empty."
            }
        }
    }

    /// Loaded rooms can only be merged once: a second merge of the same values throws `invalidRoomLocation`, on a real
    /// iPhone at least. Load them from disk again for each merge, as the export screen does.
    static func merge(_ rooms: [CapturedRoom]) async throws -> CapturedStructure {
        try await StructureBuilder(options: [.beautifyObjects]).capturedStructure(from: rooms)
    }

    static func export(project: String, floor: String, inputs: [RoomInput], to directory: URL, now: Date = Date(),
                       merge: Merge = { try await merge($0) }) async throws -> FloorExportResult {
        let (group, leftOut) = try splitBySpace(inputs)
        var warnings: [String] = []
        if !leftOut.isEmpty {
            let names = leftOut.map(\.name).joined(separator: ", ")
            warnings.append("Left out, because they were scanned in a session that couldn't be aligned with the others: \(names). Rescan them to include them.")
        }

        var structure: CapturedStructure?
        if group.count > 1 {
            do {
                let merged = try await merge(group.map(\.room))
                // StructureBuilder returns an empty structure rather than throwing on hardware it can't run on.
                guard !merged.walls.isEmpty else { throw ExportError.emptyMerge }
                structure = merged
            } catch {
                warnings.append("The rooms couldn't be merged (\(error.localizedDescription)), so they are drawn side by side and shared walls may appear twice. There is no USDZ for this floor.")
            }
        }

        let source = structure.map(GeometrySource.init) ?? GeometrySource(unmerged: group.map(\.room))
        let status: FloorDocument.MergeStatus = structure != nil ? .merged : group.count == 1 ? .singleRoom : .unmerged
        let summaries = summaries(group, merged: structure)
        let squareMetres = summaries.compactMap(\.floorAreaSquareMetres).reduce(0, +)
        if squareMetres > 186 {
            warnings.append("This floor is \(Measure.squareFeet(squareMetres)). Apple recommends merging at most about 2,000 sq ft, so check it closely.")
        }
        var document = FloorDocument(project: project, floor: floor, exportedAt: now, mergeStatus: status, rooms: summaries, source: source)
        document.unmergedRooms = leftOut.map(\.name)

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = fileName("\(project) \(floor)")
        var files: [URL] = []

        // USDZ first, so a failure there is recorded in the JSON's warnings.
        let usdz = directory.appending(path: "\(name).usdz")
        do {
            if let structure {
                try structure.export(to: usdz)
            } else if status == .singleRoom {
                try group[0].room.export(to: usdz, exportOptions: .mesh)
            }
            if status != .unmerged { files.append(usdz) }
        } catch {
            warnings.append("The 3D file couldn't be made: \(error.localizedDescription)")
        }
        document.warnings = warnings

        let pdf = directory.appending(path: "\(name)-plan.pdf")
        try PlanRenderer.pdf(document).write(to: pdf, options: .atomic)
        let image = try PlanRenderer.png(document)
        let png = directory.appending(path: "\(name)-plan.png")
        try image.write(to: png, options: .atomic)
        let json = directory.appending(path: "\(name).json")
        try encode(document).write(to: json, options: .atomic)
        files += [pdf, png, json]

        return FloorExportResult(files: files, warnings: warnings, planImage: image)
    }

    /// StructureBuilder moves and turns the whole floor and gives rooms new identifiers, but walls keep theirs, so each
    /// room is found in the structure by its walls.
    static func summaries(_ inputs: [RoomInput], merged structure: CapturedStructure?) -> [RoomSummary] {
        inputs.map { input in
            let walls = Set(input.room.walls.map(\.identifier))
            let placed = structure?.rooms.first { $0.walls.contains { walls.contains($0.identifier) } }
            return RoomSummary(name: input.name, room: input.room, placedBy: placed)
        }
    }

    /// Rooms only merge within one AR coordinate space. Takes the space with the most rooms, or the most recently
    /// scanned one when that ties, and returns the rest as left out.
    static func splitBySpace(_ inputs: [RoomInput]) throws -> (group: [RoomInput], leftOut: [RoomInput]) {
        let groups = Dictionary(grouping: inputs, by: \.spaceID).values
        let chosen = groups.max { a, b in
            if a.count != b.count { return a.count < b.count }
            return (a.map(\.scannedAt).max() ?? .distantPast) < (b.map(\.scannedAt).max() ?? .distantPast)
        }
        guard let chosen, let spaceID = chosen.first?.spaceID else { throw ExportError.noScans }
        return (chosen, inputs.filter { $0.spaceID != spaceID })
    }

    static func encode(_ document: FloorDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan")
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(document)
    }

    /// Letters and digits kept, everything else a hyphen.
    static func fileName(_ name: String) -> String {
        let parts = name.split { !$0.isLetter && !$0.isNumber }
        return parts.isEmpty ? "export" : parts.joined(separator: "-")
    }
}
