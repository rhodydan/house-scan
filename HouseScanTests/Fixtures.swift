import Foundation
import RoomPlan
import simd

/// Invented rooms, built as the JSON RoomPlan itself encodes and decoded into real CapturedRoom values, so tests
/// exercise the real types without a scan. None of this came from a real building.
///
/// They have no real `coreModel`, the private data RoomPlan keeps in every room. On a device, reloading one after saving
/// it aborts, and StructureBuilder traps on them, so neither can be caught. Device merge tests use saved real scans.
enum Fixtures {
    static let cannotReload = "A device can't reload an invented room, which has no real coreModel"

    private static let identity: [Float] = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]

    /// A transform for something that runs from `start` to `end` on the plan, centred at height `y`.
    static func transform(from start: SIMD2<Float>, to end: SIMD2<Float>, y: Float) -> [Float] {
        let direction = simd_normalize(end - start)
        let along = SIMD3<Float>(direction.x, 0, direction.y)
        let up = SIMD3<Float>(0, 1, 0)
        let normal = simd_cross(along, up)
        let middle = (start + end) / 2
        return [along.x, along.y, along.z, 0, up.x, up.y, up.z, 0, normal.x, normal.y, normal.z, 0, middle.x, y, middle.y, 1]
    }

    static func surface(_ category: [String: Any], from start: SIMD2<Float>, to end: SIMD2<Float>, height: Float = 2.4,
                        y: Float? = nil, parent: UUID? = nil, corners: [[Float]] = []) -> [String: Any] {
        [
            "category": category,
            "confidence": ["high": [String: Any]()],
            "completedEdges": [["top": [String: Any]()]],
            "curve": NSNull(),
            "dimensions": [simd_length(end - start), height, 0],
            "transform": transform(from: start, to: end, y: y ?? height / 2),
            "identifier": UUID().uuidString,
            "parentIdentifier": parent?.uuidString ?? NSNull(),
            "polygonCorners": corners,
            "story": 0,
        ]
    }

    static func object(_ category: String, at center: SIMD2<Float>, width: Float, depth: Float) -> [String: Any] {
        var matrix = identity
        matrix[12] = center.x
        matrix[13] = 0.4
        matrix[14] = center.y
        return [
            "category": [category: [String: Any]()],
            "confidence": ["medium": [String: Any]()],
            "dimensions": [width, 0.8, depth],
            "transform": matrix,
            "identifier": UUID().uuidString,
            "parentIdentifier": NSNull(),
            "attributes": ["attributes": [Any]()],
            "story": 0,
        ]
    }

    /// A rectangular room with a door in its south wall, a window in its north wall and an opening in its east wall.
    static func roomJSON(x: Float, z: Float, width: Float, depth: Float) -> [String: Any] {
        let (nw, ne) = (SIMD2(x, z), SIMD2(x + width, z))
        let (sw, se) = (SIMD2(x, z + depth), SIMD2(x + width, z + depth))
        let wall = ["wall": [String: Any]()]
        let midX = x + width / 2
        let midZ = z + depth / 2
        return [
            "version": 2,
            "identifier": UUID().uuidString,
            "story": 0,
            "walls": [
                surface(wall, from: nw, to: ne), surface(wall, from: ne, to: se),
                surface(wall, from: se, to: sw), surface(wall, from: sw, to: nw),
            ],
            "doors": [surface(["door": ["isOpen": true]], from: SIMD2(midX - 0.45, z + depth), to: SIMD2(midX + 0.45, z + depth), height: 2.0, y: 1.0)],
            "windows": [surface(["window": [String: Any]()], from: SIMD2(midX - 0.6, z), to: SIMD2(midX + 0.6, z), height: 1.2, y: 1.5)],
            "openings": [surface(["opening": [String: Any]()], from: SIMD2(x + width, midZ - 0.5), to: SIMD2(x + width, midZ + 0.5), height: 2.1, y: 1.05)],
            "floors": [surface(["floor": [String: Any]()], from: sw, to: se, height: depth, y: 0,
                               corners: [[0, 0, 0], [width, 0, 0], [width, depth, 0], [0, depth, 0]])],
            "objects": [object("sofa", at: SIMD2(midX, midZ), width: 1.8, depth: 0.9)],
            "sections": [["label": "livingRoom", "center": [midX, 0, midZ], "story": 0]],
        ]
    }

    static func decode<T: Decodable>(_ type: T.Type, _ json: [String: Any]) throws -> T {
        try JSONDecoder().decode(T.self, from: JSONSerialization.data(withJSONObject: json))
    }

    static func room(x: Float = 0, z: Float = 0, width: Float = 5, depth: Float = 4) throws -> CapturedRoom {
        try decode(CapturedRoom.self, roomJSON(x: x, z: z, width: width, depth: depth))
    }

    /// A stand-in for StructureBuilder's result, which the simulator can't produce.
    static func structure(rooms: [[String: Any]]) throws -> CapturedStructure {
        var json: [String: Any] = ["version": 2, "identifier": UUID().uuidString, "rooms": rooms]
        for key in ["walls", "doors", "windows", "openings", "floors", "objects", "sections"] {
            json[key] = rooms.flatMap { $0[key] as? [Any] ?? [] }
        }
        return try decode(CapturedStructure.self, json)
    }
}
