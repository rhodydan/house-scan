import XCTest

/// Drives the real screens against invented data. Scanning itself can't run here: the simulator has no LiDAR.
final class AppFlowTests: XCTestCase {
    private var root: URL!
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        root = FileManager.default.temporaryDirectory.appending(path: "AppFlow-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        app = XCUIApplication()
        app.launchEnvironment["HOUSE_SCAN_ROOT"] = root.path
    }

    override func tearDownWithError() throws {
        app.terminate()
        try? FileManager.default.removeItem(at: root)
    }

    private func seed() throws {
        let space = UUID().uuidString
        func room(_ name: String, x: Float, width: Float) throws -> [String: Any] {
            let id = UUID().uuidString
            let folder = root.appending(path: "rooms/\(id)", directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let json = Fixtures.roomJSON(x: x, z: 0, width: width, depth: 4)
            try JSONSerialization.data(withJSONObject: json).write(to: folder.appending(path: "captured-room.json"))
            return ["id": id, "name": name, "scan": ["scannedAt": 800_000_000.0, "spaceID": space]]
        }
        let library: [String: Any] = ["projects": [[
            "id": UUID().uuidString, "name": "Sample House", "createdAt": 800_000_000.0,
            "floors": [["id": UUID().uuidString, "name": "Main Floor",
                        "rooms": [try room("Kitchen", x: 0, width: 5), try room("Den", x: 5, width: 3)]]],
        ]]]
        try JSONSerialization.data(withJSONObject: library).write(to: root.appending(path: "library.json"))
    }

    /// Adds one invented site note to the seeded project. The simulator has no camera to take one with.
    private func seedSiteNote() throws {
        let url = root.appending(path: "library.json")
        var library = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var projects = try XCTUnwrap(library["projects"] as? [[String: Any]])
        let photos = root.appending(path: "photos", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: photos, withIntermediateDirectories: true)
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 150)).jpegData(withCompressionQuality: 0.8) { context in
            UIColor.systemGreen.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 200, height: 150))
        }
        try image.write(to: photos.appending(path: "site.jpg"))
        projects[0]["siteNotes"] = [[
            "id": UUID().uuidString, "takenAt": 800_000_000.0, "note": "North corner, by the gate", "photo": "site.jpg",
            "position": ["latitude": 12.345678, "longitude": -65.432109, "horizontalAccuracy": 8.0, "fixAgeSeconds": 1.0, "isPrecise": true],
            "heading": ["trueDegrees": 134.6, "magneticDegrees": 120.0, "accuracyDegrees": 15.0],
        ]]
        library["projects"] = projects
        try JSONSerialization.data(withJSONObject: library).write(to: url)
    }

    private func snapshot(_ name: String) {
        let url = FileManager.default.temporaryDirectory.appending(path: "ui-\(name).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        print("UI_SHOT \(url.path)")
    }

    private func enterName(_ name: String) {
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(name)
        app.alerts.buttons["Save"].tap()
    }

    func testBuildingAProjectTree() {
        app.launch()
        XCTAssertTrue(app.staticTexts["No Projects"].waitForExistence(timeout: 10))
        app.navigationBars.buttons["Add Project"].tap()
        enterName("Home")
        app.buttons["Home"].tap()
        app.buttons["Add Floor"].tap()
        enterName("Upstairs")
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Upstairs'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Scanning needs an iPhone or iPad with LiDAR."].waitForExistence(timeout: 5))
        snapshot("floor-empty")

        // It survives a relaunch.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Home"].waitForExistence(timeout: 10))
    }

    func testReopeningARoomAndExportingAFloor() throws {
        try seed()
        app.launch()
        XCTAssertTrue(app.buttons["Sample House"].waitForExistence(timeout: 10))
        app.buttons["Sample House"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Main Floor'")).firstMatch.tap()
        snapshot("floor")

        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Kitchen'")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Walls, 4"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Floor area, 215 sq ft"].exists)
        snapshot("room")
        app.navigationBars.buttons.firstMatch.tap()

        app.buttons["Merge and Export Floor"].tap()
        let shown = app.buttons["Share All"].waitForExistence(timeout: 30)
        snapshot("export")
        XCTAssertTrue(shown)
        XCTAssertTrue(app.buttons["Sample-House-Main-Floor-plan.pdf"].exists)
        XCTAssertTrue(app.buttons["Sample-House-Main-Floor-plan.png"].exists)
        XCTAssertTrue(app.buttons["Sample-House-Main-Floor.json"].exists)

        app.buttons["Share All"].tap()
        XCTAssertTrue(app.otherElements["ActivityListView"].waitForExistence(timeout: 15) || app.navigationBars["UIActivityContentView"].waitForExistence(timeout: 5))
        snapshot("share")
    }

    func testAddingAnInsuranceItemAndExportingTheInventory() throws {
        try seed()
        app.launch()
        XCTAssertTrue(app.buttons["Sample House"].waitForExistence(timeout: 10))
        app.buttons["Sample House"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Main Floor'")).firstMatch.tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Kitchen'")).firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Walls, 4"].waitForExistence(timeout: 10))
        app.swipeUp() // The item list is below the scan details.
        app.buttons["Add Item"].tap()

        let name = app.textFields["Name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.tap()
        name.typeText("Test Television")
        let serial = app.textFields["Serial number"]
        serial.tap()
        serial.typeText("SN123")
        // Value goes last, then straight to Save: it mustn't need the field to lose focus first.
        let value = app.textFields["Value in dollars"]
        value.tap()
        value.typeText("899.50")
        snapshot("item-editor")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["Test Television"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["$899.50"].exists)
        snapshot("room-items")

        // Back to the project for the whole inventory.
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Total value, $899.50"].waitForExistence(timeout: 5))
        app.buttons["Export Inventory PDF"].tap()
        XCTAssertTrue(app.buttons["Sample-House-inventory.pdf"].waitForExistence(timeout: 15))
        snapshot("inventory-export")
    }

    func testSiteNotesListAndCSVExport() throws {
        try seed()
        try seedSiteNote()
        app.launch()
        XCTAssertTrue(app.buttons["Sample House"].waitForExistence(timeout: 10))
        app.buttons["Sample House"].tap()
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Site Notes'")).firstMatch.tap()

        XCTAssertTrue(app.staticTexts["North corner, by the gate"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'within about 8 m' AND label CONTAINS 'Not survey-grade'")).firstMatch.exists)
        snapshot("site-notes")
        app.buttons["Export as CSV"].tap()
        XCTAssertTrue(app.buttons["Share CSV and Photos"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Share CSV Only"].exists)
        snapshot("site-export")
    }
}
