import Foundation

/// The plain description of a floor. It is what the JSON export writes and what the 2D plan is drawn from, and it
/// doesn't depend on RoomPlan, so nothing downstream of the mapping needs a scan to test.
///
/// Lengths are metres and angles degrees, in the scan's own frame: Y is up, and X and Z are horizontal. That frame
/// comes from where the scan started, so it has no relation to compass north.
struct FloorDocument: Codable, Equatable {
    var format = "house-scan-floor/1"
    var units = "metres, degrees"
    var coordinateSystem = "Y up, X and Z horizontal, right-handed; origin and orientation are arbitrary, set by where the scan began"
    var project: String
    var floor: String
    var exportedAt: Date
    var mergeStatus: MergeStatus
    var rooms: [RoomSummary]
    var unmergedRooms: [String] = []
    var warnings: [String] = []
    var walls: [PlanSurface]
    var doors: [PlanSurface]
    var windows: [PlanSurface]
    var openings: [PlanSurface]
    var floors: [PlanSurface]
    var objects: [PlanObject]
    var sections: [PlanSection]

    enum MergeStatus: String, Codable {
        /// StructureBuilder merged two or more rooms.
        case merged
        /// One room, so there was nothing to merge.
        case singleRoom
        /// StructureBuilder failed, so the rooms are side by side and shared walls may appear twice.
        case unmerged
    }
}

struct Vector3: Codable, Equatable {
    var x: Double
    var y: Double
    var z: Double
}

struct Quaternion: Codable, Equatable {
    var x: Double
    var y: Double
    var z: Double
    var w: Double
}

struct PlanSize: Codable, Equatable {
    var width: Double
    var height: Double
    var depth: Double
}

struct PlanRotation: Codable, Equatable {
    /// Turn about the vertical axis. A surface at 0 runs along +X.
    var yawDegrees: Double
    var quaternion: Quaternion
}

struct PlanCurve: Codable, Equatable {
    var center: [Double]
    var radius: Double
    var startAngleDegrees: Double
    var endAngleDegrees: Double
}

struct PlanSurface: Codable, Equatable, Identifiable {
    enum Kind: String, Codable {
        case wall, door, window, opening, floor, unknown
    }

    var id: UUID
    var kind: Kind
    var isOpen: Bool?
    var size: PlanSize
    var position: Vector3
    var rotation: PlanRotation
    /// The full 4x4 RoomPlan transform, column by column.
    var transform: [Double]
    var confidence: String
    var story: Int
    var parentID: UUID?
    var completedEdges: [String]
    var curve: PlanCurve?
    /// Corners in the surface's own plane, for walls and floors that aren't rectangles. Empty otherwise.
    var polygonCorners: [Vector3]
}

struct PlanObject: Codable, Equatable, Identifiable {
    var id: UUID
    var category: String
    var attributes: [String]
    var size: PlanSize
    var position: Vector3
    var rotation: PlanRotation
    var transform: [Double]
    var confidence: String
    var story: Int
    var parentID: UUID?
}

struct PlanSection: Codable, Equatable {
    var label: String
    var center: Vector3
    var story: Int
}

struct RoomSummary: Codable, Equatable {
    var name: String
    /// Middle of the room's walls, at floor level.
    var center: Vector3
    var floorAreaSquareMetres: Double?
}

/// A point on the plan: `x` and `z` are the scan's horizontal axes.
struct PlanPoint: Equatable {
    var x: Double
    var z: Double

    /// The point turned about the origin, seen from above: a positive angle turns +X towards +Z.
    func turned(by angle: Double) -> PlanPoint {
        PlanPoint(x: x * cos(angle) - z * sin(angle), z: x * sin(angle) + z * cos(angle))
    }
}

extension FloorDocument {
    /// The direction most of the wall length runs in, in radians within ±45° of +X. The scan's axes come from wherever
    /// the phone started, so a square house can come out at a slant; turning the plan back by this squares it up.
    /// Walls at right angles to each other count the same, so a long hallway and its cross walls agree.
    var mainWallDirection: Double {
        var (sine, cosine) = (0.0, 0.0)
        for wall in walls {
            let (start, end) = wall.ends
            let angle = atan2(end.z - start.z, end.x - start.x)
            guard angle.isFinite, wall.size.width.isFinite else { continue }
            sine += wall.size.width * sin(4 * angle)
            cosine += wall.size.width * cos(4 * angle)
        }
        guard sine != 0 || cosine != 0 else { return 0 }
        return atan2(sine, cosine) / 4
    }
}

extension PlanSurface {
    private var axis: PlanPoint { PlanPoint(x: transform[0], z: transform[2]) }

    /// The two ends of the surface, seen from above.
    var ends: (PlanPoint, PlanPoint) {
        let half = size.width / 2
        return (PlanPoint(x: position.x - axis.x * half, z: position.z - axis.z * half),
                PlanPoint(x: position.x + axis.x * half, z: position.z + axis.z * half))
    }
}

extension PlanObject {
    /// The object's footprint, seen from above.
    var footprint: [PlanPoint] {
        let along = PlanPoint(x: transform[0], z: transform[2])
        let across = PlanPoint(x: transform[8], z: transform[10])
        let (halfWidth, halfDepth) = (size.width / 2, size.depth / 2)
        return [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)].map { a, b in
            PlanPoint(x: position.x + a * halfWidth * along.x + b * halfDepth * across.x,
                      z: position.z + a * halfWidth * along.z + b * halfDepth * across.z)
        }
    }
}

/// Plan lengths are shown in feet and inches, and the JSON stays in metres. RoomPlan can report NaN, which Int() traps on.
enum Measure {
    static func feetAndInches(_ metres: Double) -> String {
        guard metres.isFinite else { return "unknown" }
        let inches = Int((metres / 0.0254).rounded())
        return "\(inches / 12)' \(inches % 12)\""
    }

    static func squareFeet(_ squareMetres: Double) -> String {
        guard squareMetres.isFinite else { return "unknown area" }
        return "\(Int((squareMetres * 10.7639).rounded())) sq ft"
    }
}
