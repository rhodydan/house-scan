import RoomPlan
import XCTest
@testable import HouseScan

final class GeometryTests: XCTestCase {
    func testWallMapsSizePositionAndRotation() throws {
        let document = try FloorDocument.fixture()
        XCTAssertEqual(document.walls.count, 4)

        let north = document.walls[0]
        XCTAssertEqual(north.kind, .wall)
        XCTAssertEqual(north.size, PlanSize(width: 5, height: 2.4, depth: 0))
        XCTAssertEqual(north.position, Vector3(x: 2.5, y: 1.2, z: 0))
        XCTAssertEqual(north.rotation.yawDegrees, 0)
        XCTAssertEqual(north.rotation.quaternion, Quaternion(x: 0, y: 0, z: 0, w: 1))
        XCTAssertEqual(north.confidence, "high")
        XCTAssertEqual(north.completedEdges, ["top"])
        XCTAssertEqual(north.transform.count, 16)
        XCTAssertEqual(Array(north.transform[12...14]), [2.5, 1.2, 0])
    }

    func testYawFollowsTheWall() throws {
        let document = try FloorDocument.fixture()
        // Clockwise round the room seen from above: east along +Z, south along -X, west along -Z.
        XCTAssertEqual(document.walls[1].rotation.yawDegrees, -90)
        XCTAssertEqual(abs(document.walls[2].rotation.yawDegrees), 180)
        XCTAssertEqual(document.walls[3].rotation.yawDegrees, 90)
    }

    func testQuaternionMatchesYaw() throws {
        let east = try FloorDocument.fixture().walls[1].rotation.quaternion
        // -90 degrees about Y.
        XCTAssertEqual(east.y, -sin(Double.pi / 4), accuracy: 0.001)
        XCTAssertEqual(east.w, cos(Double.pi / 4), accuracy: 0.001)
        XCTAssertEqual(east.x, 0, accuracy: 0.001)
        XCTAssertEqual(east.z, 0, accuracy: 0.001)
    }

    func testWallEndsAreItsCorners() throws {
        let east = try FloorDocument.fixture().walls[1]
        XCTAssertEqual(east.ends.0, PlanPoint(x: 5, z: 0))
        XCTAssertEqual(east.ends.1, PlanPoint(x: 5, z: 4))
    }

    func testOtherSurfaceKinds() throws {
        let document = try FloorDocument.fixture()
        XCTAssertEqual(document.doors.first?.kind, .door)
        XCTAssertEqual(document.doors.first?.isOpen, true)
        XCTAssertEqual(document.windows.first?.kind, .window)
        XCTAssertNil(document.windows.first?.isOpen)
        XCTAssertEqual(document.openings.first?.kind, .opening)
        XCTAssertEqual(document.floors.first?.kind, .floor)
    }

    func testObjectFootprint() throws {
        let sofa = try XCTUnwrap(FloorDocument.fixture().objects.first)
        XCTAssertEqual(sofa.category, "sofa")
        XCTAssertEqual(sofa.confidence, "medium")
        XCTAssertEqual(sofa.footprint.map(\.x).min()!, 1.6, accuracy: 0.001)
        XCTAssertEqual(sofa.footprint.map(\.x).max()!, 3.4, accuracy: 0.001)
        XCTAssertEqual(sofa.footprint.map(\.z).min()!, 1.55, accuracy: 0.001)
        XCTAssertEqual(sofa.footprint.map(\.z).max()!, 2.45, accuracy: 0.001)
    }

    func testRoomSummaryUsesPolygonArea() throws {
        let summary = RoomSummary(name: "Den", room: try Fixtures.room(x: 10, z: 20, width: 5, depth: 4))
        XCTAssertEqual(summary.floorAreaSquareMetres, 20)
        XCTAssertEqual(summary.center, Vector3(x: 12.5, y: 0, z: 22))
    }

    func testAreaFallsBackToBoundingBox() throws {
        var json = Fixtures.surface(["floor": [String: Any]()], from: SIMD2(0, 0), to: SIMD2(3, 0), height: 2)
        json["polygonCorners"] = [[Float]]()
        XCTAssertEqual(RoomSummary.area(of: try Fixtures.decode(CapturedRoom.Surface.self, json)), 6, accuracy: 0.001)
    }

    func testAreaOfAnLShape() throws {
        let corners: [[Float]] = [[0, 0, 0], [4, 0, 0], [4, 2, 0], [2, 2, 0], [2, 4, 0], [0, 4, 0]]
        let json = Fixtures.surface(["floor": [String: Any]()], from: SIMD2(0, 0), to: SIMD2(4, 0), height: 4, corners: corners)
        XCTAssertEqual(RoomSummary.area(of: try Fixtures.decode(CapturedRoom.Surface.self, json)), 12, accuracy: 0.001)
    }

    func testMeasureFormatting() {
        XCTAssertEqual(Measure.feetAndInches(3.048), "10' 0\"")
        XCTAssertEqual(Measure.feetAndInches(0.9144 + 0.0254 * 6), "3' 6\"")
        XCTAssertEqual(Measure.feetAndInches(0.3048 * 2 - 0.001), "2' 0\"")
        XCTAssertEqual(Measure.squareFeet(10), "108 sq ft")
    }
}
