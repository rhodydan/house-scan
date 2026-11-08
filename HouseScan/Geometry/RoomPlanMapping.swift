import Foundation
import RoomPlan
import simd

/// The parts of a CapturedRoom or CapturedStructure the exports use.
struct GeometrySource {
    var walls: [CapturedRoom.Surface]
    var doors: [CapturedRoom.Surface]
    var windows: [CapturedRoom.Surface]
    var openings: [CapturedRoom.Surface]
    var floors: [CapturedRoom.Surface]
    var objects: [CapturedRoom.Object]
    var sections: [CapturedRoom.Section]

    init(_ room: CapturedRoom) {
        walls = room.walls
        doors = room.doors
        windows = room.windows
        openings = room.openings
        floors = room.floors
        objects = room.objects
        sections = room.sections
    }

    init(_ structure: CapturedStructure) {
        walls = structure.walls
        doors = structure.doors
        windows = structure.windows
        openings = structure.openings
        floors = structure.floors
        objects = structure.objects
        sections = structure.sections
    }

    /// Rooms side by side, for when StructureBuilder can't merge them.
    init(unmerged rooms: [CapturedRoom]) {
        walls = rooms.flatMap(\.walls)
        doors = rooms.flatMap(\.doors)
        windows = rooms.flatMap(\.windows)
        openings = rooms.flatMap(\.openings)
        floors = rooms.flatMap(\.floors)
        objects = rooms.flatMap(\.objects)
        sections = rooms.flatMap(\.sections)
    }
}

extension FloorDocument {
    init(project: String, floor: String, exportedAt: Date, mergeStatus: MergeStatus, rooms: [RoomSummary], source: GeometrySource) {
        self.init(project: project, floor: floor, exportedAt: exportedAt, mergeStatus: mergeStatus, rooms: rooms,
                  walls: source.walls.map(PlanSurface.init), doors: source.doors.map(PlanSurface.init),
                  windows: source.windows.map(PlanSurface.init), openings: source.openings.map(PlanSurface.init),
                  floors: source.floors.map(PlanSurface.init), objects: source.objects.map(PlanObject.init),
                  sections: source.sections.map(PlanSection.init))
    }
}

extension RoomSummary {
    /// `placedBy` is the room as it sits in a merged structure, whose position decides where the name goes.
    init(name: String, room: CapturedRoom, placedBy placed: CapturedRoom? = nil) {
        let centers = (placed ?? room).walls.map { $0.transform.columns.3 }
        let middle = centers.isEmpty ? SIMD4<Float>.zero : centers.reduce(.zero, +) / Float(centers.count)
        let area = room.floors.map(Self.area).reduce(0, +)
        self.init(name: name, center: Vector3(x: rounded(middle.x), y: 0, z: rounded(middle.z)),
                  floorAreaSquareMetres: area > 0 ? (area * 100).rounded() / 100 : nil)
    }

    /// The polygon's area, or the bounding box's when RoomPlan gave no polygon. Corners are in the surface's own
    /// plane, so the sum of cross products works whichever way that plane faces.
    static func area(of surface: CapturedRoom.Surface) -> Double {
        let corners = surface.polygonCorners
        guard corners.count >= 3 else { return Double(surface.dimensions.x * surface.dimensions.y) }
        var sum = SIMD3<Float>.zero
        for (index, corner) in corners.enumerated() {
            sum += simd_cross(corner, corners[(index + 1) % corners.count])
        }
        return Double(simd_length(sum) / 2)
    }
}

/// A tenth of a millimetre is well past what the scanner can resolve, and keeps Float noise out of the JSON.
private func rounded(_ value: Float) -> Double {
    (Double(value) * 10_000).rounded() / 10_000
}

private extension Vector3 {
    init(_ vector: SIMD3<Float>) {
        self.init(x: rounded(vector.x), y: rounded(vector.y), z: rounded(vector.z))
    }
}

private extension PlanSize {
    init(_ dimensions: SIMD3<Float>) {
        self.init(width: rounded(dimensions.x), height: rounded(dimensions.y), depth: rounded(dimensions.z))
    }
}

private extension PlanRotation {
    init(_ transform: simd_float4x4) {
        let along = transform.columns.0
        let quaternion = simd_quatf(transform).vector
        let yaw = atan2(-Double(along.z), Double(along.x)) * 180 / .pi
        self.init(yawDegrees: (yaw * 100).rounded() / 100,
                  quaternion: Quaternion(x: rounded(quaternion.x), y: rounded(quaternion.y),
                                         z: rounded(quaternion.z), w: rounded(quaternion.w)))
    }
}

private func flattened(_ transform: simd_float4x4) -> [Double] {
    [transform.columns.0, transform.columns.1, transform.columns.2, transform.columns.3]
        .flatMap { [$0.x, $0.y, $0.z, $0.w] }
        .map(rounded)
}

private func label(_ confidence: CapturedRoom.Confidence) -> String {
    switch confidence {
    case .high: "high"
    case .medium: "medium"
    case .low: "low"
    @unknown default: "unknown"
    }
}

extension PlanSurface {
    init(_ surface: CapturedRoom.Surface) {
        let kind: Kind
        var isOpen: Bool?
        switch surface.category {
        case .wall: kind = .wall
        case .opening: kind = .opening
        case .window: kind = .window
        case .floor: kind = .floor
        case .door(let open):
            kind = .door
            isOpen = open
        @unknown default: kind = .unknown
        }
        self.init(id: surface.identifier, kind: kind, isOpen: isOpen, size: PlanSize(surface.dimensions),
                  position: Vector3(simd_make_float3(surface.transform.columns.3)),
                  rotation: PlanRotation(surface.transform), transform: flattened(surface.transform),
                  confidence: label(surface.confidence), story: surface.story, parentID: surface.parentIdentifier,
                  completedEdges: surface.completedEdges.map(Self.name).sorted(),
                  curve: surface.curve.map(PlanCurve.init), polygonCorners: surface.polygonCorners.map(Vector3.init))
    }

    private static func name(_ edge: CapturedRoom.Surface.Edge) -> String {
        switch edge {
        case .top: "top"
        case .right: "right"
        case .bottom: "bottom"
        case .left: "left"
        @unknown default: "unknown"
        }
    }
}

private extension PlanCurve {
    init(_ curve: CapturedRoom.Surface.Curve) {
        self.init(center: [rounded(curve.center.x), rounded(curve.center.y)], radius: rounded(curve.radius),
                  startAngleDegrees: curve.startAngle.converted(to: .degrees).value,
                  endAngleDegrees: curve.endAngle.converted(to: .degrees).value)
    }
}

extension PlanObject {
    init(_ object: CapturedRoom.Object) {
        self.init(id: object.identifier, category: Self.name(object.category), attributes: object.attributes.map { $0.rawValue },
                  size: PlanSize(object.dimensions), position: Vector3(simd_make_float3(object.transform.columns.3)),
                  rotation: PlanRotation(object.transform), transform: flattened(object.transform),
                  confidence: label(object.confidence), story: object.story, parentID: object.parentIdentifier)
    }

    private static func name(_ category: CapturedRoom.Object.Category) -> String {
        switch category {
        case .storage: "storage"
        case .refrigerator: "refrigerator"
        case .stove: "stove"
        case .bed: "bed"
        case .sink: "sink"
        case .washerDryer: "washer/dryer"
        case .toilet: "toilet"
        case .bathtub: "bathtub"
        case .oven: "oven"
        case .dishwasher: "dishwasher"
        case .table: "table"
        case .sofa: "sofa"
        case .chair: "chair"
        case .fireplace: "fireplace"
        case .television: "television"
        case .stairs: "stairs"
        @unknown default: "unknown"
        }
    }
}

extension PlanSection {
    init(_ section: CapturedRoom.Section) {
        self.init(label: section.label.rawValue, center: Vector3(section.center), story: section.story)
    }
}
