import UIKit

/// The items going into an inventory, in order.
struct InventoryReport {
    struct Entry {
        var floor: String
        var room: String
        var item: InventoryItem
    }

    var title: String
    var generatedAt: Date
    var entries: [Entry]

    var totalCents: Int { entries.compactMap(\.item.valueCents).reduce(0, +) }
    var unvaluedCount: Int { entries.filter { $0.item.valueCents == nil }.count }

    static func money(cents: Int) -> String {
        (Decimal(cents) / 100).formatted(.currency(code: "USD"))
    }
}

extension Project {
    /// Every item in the project, or one room's when `onlyRoom` is set.
    func inventory(onlyRoom: Room.ID? = nil, generatedAt: Date = Date()) -> InventoryReport {
        var entries: [InventoryReport.Entry] = []
        for floor in floors {
            for room in floor.rooms where onlyRoom == nil || room.id == onlyRoom {
                entries += room.items.map { InventoryReport.Entry(floor: floor.name, room: room.name, item: $0) }
            }
        }
        return InventoryReport(title: name, generatedAt: generatedAt, entries: entries)
    }
}

/// Lays the report out as pages of drawing steps, then draws them. Knowing the pages first gives "Page 2 of 5".
enum InventoryPDF {
    enum Step {
        case text(String, UIFont, UIColor, CGRect)
        case photo(URL, CGRect)
        case rule(CGFloat)
    }

    private static let page = CGRect(x: 0, y: 0, width: 612, height: 792)
    private static let margin: CGFloat = 48
    private static let photosPerRow = 3
    private static let gap: CGFloat = 8
    private static var contentWidth: CGFloat { page.width - 2 * margin }
    private static var bottom: CGFloat { page.height - margin - 20 }

    private static let titleFont = UIFont.boldSystemFont(ofSize: 20)
    private static let headingFont = UIFont.boldSystemFont(ofSize: 13)
    private static let nameFont = UIFont.boldSystemFont(ofSize: 11)
    private static let bodyFont = UIFont.systemFont(ofSize: 10)

    static func make(_ report: InventoryReport, photoURL: (String) -> URL) -> Data {
        let pages = layout(report, photoURL: photoURL)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "\(report.title) inventory", kCGPDFContextCreator as String: "House Scan"]
        return UIGraphicsPDFRenderer(bounds: page, format: format).pdfData { context in
            for (index, steps) in pages.enumerated() {
                context.beginPage()
                steps.forEach { draw($0, in: context.cgContext) }
                let footer = "\(report.title) inventory, \(report.generatedAt.formatted(date: .abbreviated, time: .omitted)). Page \(index + 1) of \(pages.count)"
                draw(.text(footer, .systemFont(ofSize: 8), .darkGray, CGRect(x: margin, y: page.height - margin, width: contentWidth, height: 12)), in: context.cgContext)
            }
        }
    }

    static func layout(_ report: InventoryReport, photoURL: (String) -> URL) -> [[Step]] {
        var pages: [[Step]] = [[]]
        var y = margin

        func add(_ step: Step) { pages[pages.count - 1].append(step) }
        func newPage() {
            pages.append([])
            y = margin
        }
        func ensure(_ height: CGFloat) {
            if y + height > bottom { newPage() }
        }
        func line(_ text: String, _ font: UIFont, _ color: UIColor = .black) {
            let height = measure(text, font)
            ensure(height)
            add(.text(text, font, color, CGRect(x: margin, y: y, width: contentWidth, height: height)))
            y += height + 2
        }
        /// Text that may run over the page, split at a word so none of it is lost.
        func paragraph(_ text: String, _ font: UIFont, _ color: UIColor) {
            var rest = text
            while !rest.isEmpty {
                if bottom - y < font.lineHeight * 2 { newPage() }
                let (head, tail) = split(rest, font, maxHeight: bottom - y)
                let height = measure(head, font)
                add(.text(head, font, color, CGRect(x: margin, y: y, width: contentWidth, height: height)))
                y += height + 2
                rest = tail
            }
        }

        line("\(report.title): Home Inventory", titleFont)
        line("Generated \(report.generatedAt.formatted(date: .long, time: .omitted))", bodyFont, .darkGray)
        var summary = "\(report.entries.count) item\(report.entries.count == 1 ? "" : "s"). Total value entered: \(InventoryReport.money(cents: report.totalCents))."
        if report.unvaluedCount > 0 { summary += " \(report.unvaluedCount) with no value entered." }
        line(summary, bodyFont)
        line("Values and details are the owner's own entries, not an appraisal.", bodyFont, .darkGray)
        y += 8

        var currentRoom: String?
        for entry in report.entries {
            let roomTitle = "\(entry.floor): \(entry.room)"
            if roomTitle != currentRoom {
                currentRoom = roomTitle
                y += 8
                ensure(measure(roomTitle, headingFont) + 60)
                add(.rule(y))
                y += 6
                line(roomTitle, headingFont)
                y += 2
            }
            let item = entry.item
            ensure(measure(item.name, nameFont) + 30)
            line(item.name, nameFont)
            var facts: [String] = [item.valueCents.map { "Value: " + InventoryReport.money(cents: $0) } ?? "Value: not entered"]
            if !item.model.isEmpty { facts.append("Model: \(item.model)") }
            if !item.serialNumber.isEmpty { facts.append("Serial: \(item.serialNumber)") }
            line(facts.joined(separator: "   "), bodyFont)
            if item.needsChecking { line("Model and serial read automatically from the label photo, not yet checked.", bodyFont) }
            if !item.notes.isEmpty { paragraph(item.notes, bodyFont, .darkGray) }

            let cell = (contentWidth - gap * CGFloat(photosPerRow - 1)) / CGFloat(photosPerRow)
            let cellHeight = cell * 0.75
            for start in stride(from: 0, to: item.photos.count, by: photosPerRow) {
                ensure(cellHeight + gap)
                for (column, name) in item.photos[start..<min(start + photosPerRow, item.photos.count)].enumerated() {
                    add(.photo(photoURL(name), CGRect(x: margin + CGFloat(column) * (cell + gap), y: y, width: cell, height: cellHeight)))
                }
                y += cellHeight + gap
            }
            y += 10
        }
        return pages
    }

    private static func measure(_ text: String, _ font: UIFont) -> CGFloat {
        ceil((text as NSString).boundingRect(with: CGSize(width: contentWidth, height: .greatestFiniteMagnitude),
                                             options: [.usesLineFragmentOrigin], attributes: [.font: font], context: nil).height)
    }

    /// The most of `text` that fits in `maxHeight`, ending at a word break, and the remainder.
    private static func split(_ text: String, _ font: UIFont, maxHeight: CGFloat) -> (String, String) {
        if measure(text, font) <= maxHeight { return (text, "") }
        let characters = Array(text)
        var low = 0, high = characters.count
        while low < high {
            let middle = (low + high + 1) / 2
            if measure(String(characters[..<middle]), font) <= maxHeight { low = middle } else { high = middle - 1 }
        }
        var end = max(low, 1)
        if let space = characters[..<end].lastIndex(where: \.isWhitespace), space > 0 { end = space + 1 }
        return (String(characters[..<end]).trimmingCharacters(in: .whitespacesAndNewlines),
                String(characters[end...]).trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func draw(_ step: Step, in context: CGContext) {
        switch step {
        case .text(let text, let font, let color, let rect):
            (text as NSString).draw(with: rect, options: [.usesLineFragmentOrigin], attributes: [.font: font, .foregroundColor: color], context: nil)
        case .photo(let url, let rect):
            guard let image = PhotoPreparation.thumbnail(at: url, longestEdge: 1000) else {
                context.setStrokeColor(UIColor.lightGray.cgColor)
                context.stroke(rect)
                return
            }
            let scale = min(rect.width / image.size.width, rect.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            image.draw(in: CGRect(origin: CGPoint(x: rect.minX, y: rect.minY + (rect.height - size.height) / 2), size: size))
        case .rule(let y):
            context.setStrokeColor(UIColor.lightGray.cgColor)
            context.setLineWidth(0.5)
            context.strokeLineSegments(between: [CGPoint(x: margin, y: y), CGPoint(x: page.width - margin, y: y)])
        }
    }
}
