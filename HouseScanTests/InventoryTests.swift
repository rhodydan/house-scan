import ImageIO
import PDFKit
import UIKit
import UniformTypeIdentifiers
import XCTest
@testable import HouseScan

final class InventoryTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func report(_ items: [InventoryItem]) -> InventoryReport {
        InventoryReport(title: "Sample House", generatedAt: date,
                        entries: items.map { .init(floor: "Main Floor", room: "Den", item: $0) })
    }

    private func text(_ pdf: PDFDocument) -> String {
        (0..<pdf.pageCount).compactMap { pdf.page(at: $0)?.string }.joined(separator: "\n")
    }

    private func make(_ report: InventoryReport, photos: URL? = nil) throws -> PDFDocument {
        let data = InventoryPDF.make(report) { photos?.appending(path: $0) ?? URL(filePath: "/nonexistent/\($0)") }
        return try XCTUnwrap(PDFDocument(data: data))
    }

    func testCentsAreExact() {
        XCTAssertEqual(InventoryItem.cents(Decimal(string: "1299.99")!), 129_999)
        XCTAssertEqual(InventoryItem.cents(Decimal(string: "0.1")!), 10)
        XCTAssertEqual(InventoryItem.cents(Decimal(string: "19.995")!), 2000)
        XCTAssertEqual(InventoryItem.cents(0), 0)
    }

    func testTypedValues() {
        XCTAssertEqual(InventoryItem.cents(typed: "899.50"), 89_950)
        XCTAssertEqual(InventoryItem.cents(typed: "$1,299.99"), 129_999)
        XCTAssertEqual(InventoryItem.cents(typed: "40"), 4000)
        XCTAssertEqual(InventoryItem.cents(typed: ".5"), 50)
        XCTAssertEqual(InventoryItem.cents(typed: "5."), 500)
        XCTAssertNil(InventoryItem.cents(typed: "12abc"))
        XCTAssertNil(InventoryItem.cents(typed: "1.2.3"))
        XCTAssertNil(InventoryItem.cents(typed: "-5"))
        XCTAssertNil(InventoryItem.cents(typed: ""))
    }

    func testTotalsAndMoney() {
        let report = report([InventoryItem(name: "A", valueCents: 129_999), InventoryItem(name: "B", valueCents: 1), InventoryItem(name: "C")])
        XCTAssertEqual(report.totalCents, 130_000)
        XCTAssertEqual(report.unvaluedCount, 1)
        XCTAssertEqual(InventoryReport.money(cents: 130_000), "$1,300.00")
    }

    func testPDFListsItemsAndTotals() throws {
        let item = InventoryItem(name: "Test Television", notes: "Wall mounted", serialNumber: "SN-00123", valueCents: 89_900)
        let text = text(try make(report([item, InventoryItem(name: "Old Lamp")])))
        for expected in ["Sample House: Home Inventory", "Main Floor: Den", "Test Television", "SN-00123", "$899.00", "Wall mounted",
                         "Old Lamp", "not entered", "1 with no value entered", "not an appraisal", "Page 1 of 1"] {
            XCTAssertTrue(text.contains(expected), "Missing \(expected) in \(text)")
        }
    }

    func testManyItemsPaginateWithAFooterOnEachPage() throws {
        let items = (1...60).map { InventoryItem(name: "Item \($0)", valueCents: 100) }
        let pdf = try make(report(items))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        let all = text(pdf)
        for number in 1...60 { XCTAssertTrue(all.contains("Item \(number)\n") || all.contains("Item \(number)"), "Lost item \(number)") }
        XCTAssertTrue(all.contains("Page \(pdf.pageCount) of \(pdf.pageCount)"))
    }

    func testVeryLongNotesAreNeverCutOff() throws {
        let words = (1...4000).map { "word\($0)" }
        let pdf = try make(report([InventoryItem(name: "Long", notes: words.joined(separator: " "))]))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        let all = text(pdf).replacingOccurrences(of: "\n", with: " ")
        for word in ["word1 ", "word2000 ", "word3999 ", "word4000"] {
            XCTAssertTrue(all.contains(word), "Lost \(word)")
        }
    }

    func testNothingRunsPastTheBottomOfThePage() {
        let items = (1...20).map { InventoryItem(name: "Item \($0)", notes: String(repeating: "note ", count: 200), photos: ["a", "b", "c", "d"]) }
        let pages = InventoryPDF.layout(report(items)) { URL(filePath: "/nonexistent/\($0)") }
        for steps in pages {
            for step in steps {
                switch step {
                case .text(_, _, _, let rect), .photo(_, let rect): XCTAssertLessThanOrEqual(rect.maxY, 792 - 48 - 20 + 0.5)
                case .rule: break
                }
            }
        }
    }

    func testPhotosGoIntoThePDF() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "InventoryPhotos-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try XCTUnwrap(PhotoPreparation.jpeg(from: solidImage(CGSize(width: 800, height: 600)))).write(to: folder.appending(path: "p.jpg"))

        let plain = InventoryPDF.make(report([InventoryItem(name: "A")])) { folder.appending(path: $0) }
        let withPhoto = InventoryPDF.make(report([InventoryItem(name: "A", photos: ["p.jpg"])])) { folder.appending(path: $0) }
        XCTAssertGreaterThan(withPhoto.count, plain.count + 1000)
    }

    func testProjectInventoryCanBeOneRoom() {
        let den = Room(name: "Den", items: [InventoryItem(name: "A")])
        let attic = Room(name: "Attic", items: [InventoryItem(name: "B"), InventoryItem(name: "C")])
        let project = Project(name: "Sample", floors: [Floor(name: "Main", rooms: [den]), Floor(name: "Top", rooms: [attic])])
        XCTAssertEqual(project.inventory().entries.map(\.item.name), ["A", "B", "C"])
        XCTAssertEqual(project.inventory(onlyRoom: attic.id).entries.map(\.room), ["Attic", "Attic"])
    }

    // MARK: Photos

    private func solidImage(_ size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func jpegWithGPSTag() throws -> Data {
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        let gps: [CFString: Any] = [kCGImagePropertyGPSLatitude: 12.3456, kCGImagePropertyGPSLatitudeRef: "N",
                                    kCGImagePropertyGPSLongitude: 65.4321, kCGImagePropertyGPSLongitudeRef: "W"]
        let exif: [CFString: Any] = [kCGImagePropertyExifUserComment: "invented"]
        CGImageDestinationAddImage(destination, try XCTUnwrap(solidImage(CGSize(width: 64, height: 64)).cgImage),
                                   [kCGImagePropertyGPSDictionary: gps, kCGImagePropertyExifDictionary: exif] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func properties(_ data: Data) throws -> [CFString: Any] {
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data as CFData, nil))
        return try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
    }

    func testPreparedPhotosCarryNoGPSTag() throws {
        let original = try jpegWithGPSTag()
        XCTAssertNotNil(try properties(original)[kCGImagePropertyGPSDictionary], "The test photo should start with a GPS tag")
        let prepared = try XCTUnwrap(PhotoPreparation.jpeg(from: original))
        XCTAssertNil(try properties(prepared)[kCGImagePropertyGPSDictionary])
    }

    func testBigPhotosShrinkAndSmallOnesDoNot() throws {
        let big = try XCTUnwrap(PhotoPreparation.jpeg(from: solidImage(CGSize(width: 6000, height: 4000))))
        let bigImage = try XCTUnwrap(UIImage(data: big))
        XCTAssertEqual(bigImage.size.width, 3000)
        XCTAssertEqual(bigImage.size.height, 2000)
        let small = try XCTUnwrap(PhotoPreparation.jpeg(from: solidImage(CGSize(width: 400, height: 300))))
        XCTAssertEqual(try XCTUnwrap(UIImage(data: small)).size.width, 400)
    }

    func testRotatedPhotosStayUpright() throws {
        let landscape = try XCTUnwrap(solidImage(CGSize(width: 400, height: 300)).cgImage)
        let rotated = UIImage(cgImage: landscape, scale: 1, orientation: .right)
        let prepared = try XCTUnwrap(UIImage(data: try XCTUnwrap(PhotoPreparation.jpeg(from: rotated))))
        XCTAssertEqual(prepared.size, CGSize(width: 300, height: 400))
        XCTAssertEqual(prepared.imageOrientation, .up)
    }

    func testLabelItemsShowTheirModelAndThatTheyNeedChecking() throws {
        let label = InventoryItem(reading: LabelReading(make: "Bosch", model: "SHX-TEST", serial: "FD1234"), photo: "none.jpg")
        var checked = label
        checked.needsChecking = false
        let text = text(try make(report([label])))
        XCTAssertTrue(text.contains("Model: SHX-TEST"))
        XCTAssertTrue(text.contains("not yet checked"))
        XCTAssertFalse(self.text(try make(report([checked]))).contains("not yet checked"))
    }
}
