import UIKit
import XCTest
@testable import HouseScan

/// Invented labels. No real make, model or serial from the house.
final class LabelTests: XCTestCase {
    func testKeywordsAndValuesOnOneLine() {
        let reading = LabelReading(lines: ["Samsung Electronics", "MODEL: WF45-TEST1", "S/N: 0B7JTEST1234"])
        XCTAssertEqual(reading, LabelReading(make: "Samsung", model: "WF45-TEST1", serial: "0B7JTEST1234"))
    }

    func testValuesBelowTheirKeywords() {
        XCTAssertEqual(LabelReading(lines: ["Model No.", "AB-1234", "Serial No.", "XY987654"]).model, "AB-1234")
        XCTAssertEqual(LabelReading(lines: ["Model No.", "AB-1234", "Serial No.", "XY987654"]).serial, "XY987654")
    }

    func testSideBySideColumnsFillInOrder() {
        let reading = LabelReading(lines: ["MODEL NO.", "SERIAL NO.", "AB-1234", "XY987654"])
        XCTAssertEqual(reading.model, "AB-1234")
        XCTAssertEqual(reading.serial, "XY987654")
    }

    func testBothOnOneLine() {
        let reading = LabelReading(lines: ["MOD. NO. KX100 SER. NO. 12345678"])
        XCTAssertEqual(reading.model, "KX100")
        XCTAssertEqual(reading.serial, "12345678")
    }

    func testRatingsAreNotModelNumbers() {
        XCTAssertEqual(LabelReading(lines: ["MODEL", "120V", "60Hz", "LX-200"]).model, "LX-200")
    }

    func testCommonMisreadOfSlashN() {
        XCTAssertEqual(LabelReading(lines: ["SIN: QW12345"]).serial, "QW12345")
    }

    func testWordsAfterAKeywordAreNotAValue() {
        let reading = LabelReading(lines: ["Serial number is on the back", "Made in USA"])
        XCTAssertTrue(reading.isEmpty)
    }

    func testBarcodeFixesLookAlikeCharacters() {
        XCTAssertEqual(LabelReading(lines: ["S/N: X1O0234"], barcodes: ["X100234"]).serial, "X100234")
    }

    func testOneSpareBarcodeFillsAMissingSerial() {
        let reading = LabelReading(lines: ["MODEL: AB123"], barcodes: ["AB123", "SN99887766"])
        XCTAssertEqual(reading.serial, "SN99887766")
        XCTAssertTrue(LabelReading(lines: ["MODEL: AB123"], barcodes: ["P1234567", "Q7654321"]).serial.isEmpty)
    }

    func testItemFromALabelIsNamedAndMarkedForChecking() {
        let item = InventoryItem(reading: LabelReading(make: "Bosch", model: "SHX-TEST", serial: "FD1234"), photo: "a.jpg")
        XCTAssertEqual(item.name, "Bosch SHX-TEST")
        XCTAssertEqual(item.serialNumber, "FD1234")
        XCTAssertEqual(item.photos, ["a.jpg"])
        XCTAssertTrue(item.needsChecking)
        XCTAssertEqual(InventoryItem(reading: LabelReading(), photo: "b.jpg").name, "Label photo")
    }

    func testItemsSavedBeforeLabelScanningStillLoad() throws {
        let json = #"{"id":"6F1C3C1E-0000-4000-8000-000000000001","name":"Lamp","notes":"","serialNumber":"S1","photos":[]}"#
        let item = try JSONDecoder().decode(InventoryItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.model, "")
        XCTAssertFalse(item.needsChecking)
    }

    /// Vision itself, on a label drawn here.
    func testVisionReadsADrawnLabel() throws {
        let size = CGSize(width: 1400, height: 700)
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let font = UIFont.monospacedSystemFont(ofSize: 64, weight: .semibold)
            for (index, line) in ["WHIRLPOOL", "MODEL: WTW5TEST7", "SERIAL: C12345678", "120V 60Hz 10A"].enumerated() {
                (line as NSString).draw(at: CGPoint(x: 80, y: 80 + index * 140), withAttributes: [.font: font, .foregroundColor: UIColor.black])
            }
        }
        let jpeg = try XCTUnwrap(PhotoPreparation.jpeg(from: image))
        let reading = LabelReader.read(jpeg: jpeg)
        XCTAssertEqual(reading.make, "Whirlpool")
        XCTAssertEqual(reading.model, "WTW5TEST7")
        XCTAssertEqual(reading.serial, "C12345678")
    }
}
