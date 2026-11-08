import Foundation
import RoomPlan
@testable import HouseScan

extension Fixtures {
    static func input(_ name: String, space: UUID, x: Float = 0, width: Float = 5, depth: Float = 4,
                      date: Date = Date(timeIntervalSince1970: 1_800_000_000)) throws -> RoomInput {
        RoomInput(name: name, spaceID: space, scannedAt: date, room: try room(x: x, width: width, depth: depth))
    }
}

extension FloorDocument {
    static func fixture(project: String = "Sample House", floor: String = "Main Floor") throws -> FloorDocument {
        let room = try Fixtures.room()
        return FloorDocument(project: project, floor: floor, exportedAt: Date(timeIntervalSince1970: 1_800_000_000),
                             mergeStatus: .singleRoom, rooms: [RoomSummary(name: "Living Room", room: room)], source: GeometrySource(room))
    }
}
