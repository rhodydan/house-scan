import UIKit

/// Where the plan sits on a page: one uniform scale, with the scan's X to the right and Z down the page. That is the
/// view from above, so the plan isn't mirrored. The plan is turned so most walls run square to the page.
struct PlanLayout {
    let scale: Double
    /// The plan's turn on the page, in radians.
    let turn: Double
    private let origin: PlanPoint
    private let area: CGRect

    init?(_ document: FloorDocument, area: CGRect) {
        let turn = -document.mainWallDirection
        self.turn = turn
        let points = (document.walls.flatMap { [$0.ends.0, $0.ends.1] } + document.objects.flatMap(\.footprint)).map { $0.turned(by: turn) }
        guard let minX = points.map(\.x).min(), let maxX = points.map(\.x).max(),
              let minZ = points.map(\.z).min(), let maxZ = points.map(\.z).max() else { return nil }
        let width = max(maxX - minX, 0.1)
        let depth = max(maxZ - minZ, 0.1)
        scale = min(area.width / width, area.height / depth)
        origin = PlanPoint(x: (minX + maxX) / 2, z: (minZ + maxZ) / 2)
        self.area = area
    }

    func point(_ plan: PlanPoint) -> CGPoint {
        let turned = plan.turned(by: turn)
        return CGPoint(x: area.midX + (turned.x - origin.x) * scale, y: area.midY + (turned.z - origin.z) * scale)
    }
}

/// Draws the 2D floor plan. The PDF and PNG share `draw`, so they can't drift apart.
enum PlanRenderer {
    enum RenderError: LocalizedError {
        case nothingToDraw
        var errorDescription: String? { "This floor has no walls to draw." }
    }

    private static let margin: CGFloat = 36
    private static let wallColor = UIColor(white: 0.1, alpha: 1)
    private static let doorColor = UIColor(red: 0.72, green: 0.33, blue: 0.1, alpha: 1)
    private static let windowColor = UIColor(red: 0.1, green: 0.45, blue: 0.8, alpha: 1)
    private static let openingColor = UIColor(white: 0.55, alpha: 1)
    private static let objectColor = UIColor(white: 0.6, alpha: 1)

    /// US Letter, turned to suit the plan.
    static func pageSize(for document: FloorDocument) -> CGSize {
        let turn = -document.mainWallDirection
        let points = document.walls.flatMap { [$0.ends.0, $0.ends.1] }.map { $0.turned(by: turn) }
        let width = (points.map(\.x).max() ?? 0) - (points.map(\.x).min() ?? 0)
        let depth = (points.map(\.z).max() ?? 0) - (points.map(\.z).min() ?? 0)
        return width >= depth ? CGSize(width: 792, height: 612) : CGSize(width: 612, height: 792)
    }

    static func pdf(_ document: FloorDocument) throws -> Data {
        guard !document.walls.isEmpty else { throw RenderError.nothingToDraw }
        let page = CGRect(origin: .zero, size: pageSize(for: document))
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: "\(document.project) - \(document.floor)",
                               kCGPDFContextCreator as String: "House Scan"]
        return UIGraphicsPDFRenderer(bounds: page, format: format).pdfData { context in
            context.beginPage()
            draw(document, in: context.cgContext, size: page.size)
        }
    }

    static func png(_ document: FloorDocument) throws -> Data {
        guard !document.walls.isEmpty else { throw RenderError.nothingToDraw }
        let size = pageSize(for: document)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 4
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            draw(document, in: context.cgContext, size: size)
        }
    }

    static func draw(_ document: FloorDocument, in context: CGContext, size: CGSize) {
        let title = document.floor == document.project ? document.project : "\(document.project) - \(document.floor)"
        text(title, at: CGPoint(x: margin, y: margin - 12), font: .boldSystemFont(ofSize: 15), color: .black)
        let area = CGRect(x: margin + 26, y: margin + 40, width: size.width - 2 * margin - 52, height: size.height - 2 * margin - 96)
        guard let layout = PlanLayout(document, area: area) else { return }

        document.objects.forEach { drawObject($0, layout, in: context) }
        document.walls.forEach { stroke($0, layout, width: 3.5, color: wallColor, in: context) }
        document.openings.forEach { drawGap($0, layout, color: openingColor, in: context) }
        document.doors.forEach { drawGap($0, layout, color: doorColor, in: context) }
        document.windows.forEach { drawGap($0, layout, color: windowColor, in: context) }
        let labels = roomLabels(document, layout)
        drawWallLengths(document, layout, avoiding: labels.map(\.frame), in: context)
        labels.forEach(drawRoomLabel)
        drawFooter(document, layout, size: size, in: context)
    }

    private static func stroke(_ surface: PlanSurface, _ layout: PlanLayout, width: CGFloat, color: UIColor, in context: CGContext) {
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.setLineCap(.butt)
        context.strokeLineSegments(between: [layout.point(surface.ends.0), layout.point(surface.ends.1)])
    }

    /// Clears the wall under a door, window or opening and draws its symbol in the gap. RoomPlan doesn't report
    /// which way a door swings, so doors have no swing arc.
    private static func drawGap(_ surface: PlanSurface, _ layout: PlanLayout, color: UIColor, in context: CGContext) {
        let (start, end) = (layout.point(surface.ends.0), layout.point(surface.ends.1))
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(5.5)
        context.setLineCap(.butt)
        context.strokeLineSegments(between: [start, end])

        let dx = end.x - start.x, dy = end.y - start.y
        let length = max(hypot(dx, dy), 0.001)
        let offset = CGPoint(x: -dy / length * 2.2, y: dx / length * 2.2)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(1)
        context.strokeLineSegments(between: [
            CGPoint(x: start.x + offset.x, y: start.y + offset.y), CGPoint(x: end.x + offset.x, y: end.y + offset.y),
            CGPoint(x: start.x - offset.x, y: start.y - offset.y), CGPoint(x: end.x - offset.x, y: end.y - offset.y),
            CGPoint(x: start.x + offset.x, y: start.y + offset.y), CGPoint(x: start.x - offset.x, y: start.y - offset.y),
            CGPoint(x: end.x + offset.x, y: end.y + offset.y), CGPoint(x: end.x - offset.x, y: end.y - offset.y),
        ])
    }

    private static func drawObject(_ object: PlanObject, _ layout: PlanLayout, in context: CGContext) {
        let corners = object.footprint.map(layout.point)
        context.setStrokeColor(objectColor.cgColor)
        context.setLineWidth(0.6)
        context.addLines(between: corners)
        context.closePath()
        context.strokePath()

        let center = CGPoint(x: corners.map(\.x).reduce(0, +) / 4, y: corners.map(\.y).reduce(0, +) / 4)
        let width = hypot(corners[1].x - corners[0].x, corners[1].y - corners[0].y)
        let font = UIFont.systemFont(ofSize: 6)
        if width > (object.category as NSString).size(withAttributes: [.font: font]).width + 2 {
            text(object.category, centeredAt: center, font: font, color: objectColor)
        }
    }

    /// Each wall's length, set along the wall on the side away from the middle of the plan. Longer walls go first, and
    /// a length that would land on a room label or another length is left off; the JSON still has every one.
    private static func drawWallLengths(_ document: FloorDocument, _ layout: PlanLayout, avoiding taken: [CGRect], in context: CGContext) {
        let ends = document.walls.flatMap { [layout.point($0.ends.0), layout.point($0.ends.1)] }
        guard !ends.isEmpty else { return }
        let middle = CGPoint(x: ends.map(\.x).reduce(0, +) / CGFloat(ends.count), y: ends.map(\.y).reduce(0, +) / CGFloat(ends.count))
        let font = UIFont.systemFont(ofSize: 7.5)
        var taken = taken

        for wall in document.walls.filter({ $0.size.width >= 0.5 }).sorted(by: { $0.size.width > $1.size.width }) {
            let (start, end) = (layout.point(wall.ends.0), layout.point(wall.ends.1))
            let center = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
            let dx = end.x - start.x, dy = end.y - start.y
            let length = max(hypot(dx, dy), 0.001)
            var normal = CGPoint(x: -dy / length, y: dx / length)
            if (center.x - middle.x) * normal.x + (center.y - middle.y) * normal.y < 0 {
                normal = CGPoint(x: -normal.x, y: -normal.y)
            }
            var angle = atan2(dy, dx)
            if angle > .pi / 2 { angle -= .pi } else if angle <= -.pi / 2 { angle += .pi }

            let label = Measure.feetAndInches(wall.size.width)
            let position = CGPoint(x: center.x + normal.x * 10, y: center.y + normal.y * 10)
            let frame = turnedFrame((label as NSString).size(withAttributes: [.font: font]), angle: angle, centeredAt: position)
            guard !taken.contains(where: { $0.intersects(frame) }) else { continue }
            taken.append(frame)

            context.saveGState()
            context.translateBy(x: position.x, y: position.y)
            context.rotate(by: angle)
            text(label, centeredAt: .zero, font: font, color: UIColor(white: 0.25, alpha: 1))
            context.restoreGState()
        }
    }

    /// The upright box around text of `size` turned by `angle`.
    private static func turnedFrame(_ size: CGSize, angle: CGFloat, centeredAt center: CGPoint) -> CGRect {
        let width = abs(size.width * cos(angle)) + abs(size.height * sin(angle))
        let height = abs(size.width * sin(angle)) + abs(size.height * cos(angle))
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
    }

    private static let roomNameFont = UIFont.boldSystemFont(ofSize: 10)
    private static let roomAreaFont = UIFont.systemFont(ofSize: 8)

    struct RoomLabel {
        var name: String
        var area: String?
        var frame: CGRect
    }

    /// Each room's name and area, centred on the room, with labels that would overlap pushed apart up and down the page.
    static func roomLabels(_ document: FloorDocument, _ layout: PlanLayout) -> [RoomLabel] {
        var labels = document.rooms.map { room in
            let area = room.floorAreaSquareMetres.map(Measure.squareFeet)
            let nameSize = (room.name as NSString).size(withAttributes: [.font: roomNameFont])
            let areaSize = area.map { ($0 as NSString).size(withAttributes: [.font: roomAreaFont]) } ?? .zero
            let size = CGSize(width: max(nameSize.width, areaSize.width), height: nameSize.height + areaSize.height)
            let center = layout.point(PlanPoint(x: room.center.x, z: room.center.z))
            return RoomLabel(name: room.name, area: area,
                             frame: CGRect(x: center.x - size.width / 2, y: center.y - nameSize.height / 2, width: size.width, height: size.height))
        }
        for _ in 0..<50 {
            var moved = false
            for i in labels.indices {
                for j in labels.indices where j > i {
                    let overlap = labels[i].frame.insetBy(dx: -1, dy: -1).intersection(labels[j].frame)
                    guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
                    let push = overlap.height / 2 + 0.5
                    let iGoesUp = labels[i].frame.midY <= labels[j].frame.midY
                    labels[i].frame.origin.y += iGoesUp ? -push : push
                    labels[j].frame.origin.y += iGoesUp ? push : -push
                    moved = true
                }
            }
            if !moved { break }
        }
        return labels
    }

    private static func drawRoomLabel(_ label: RoomLabel) {
        let nameHeight = (label.name as NSString).size(withAttributes: [.font: roomNameFont]).height
        text(label.name, centeredAt: CGPoint(x: label.frame.midX, y: label.frame.minY + nameHeight / 2), font: roomNameFont,
             color: .black, background: .white)
        if let area = label.area {
            let areaHeight = (area as NSString).size(withAttributes: [.font: roomAreaFont]).height
            text(area, centeredAt: CGPoint(x: label.frame.midX, y: label.frame.minY + nameHeight + areaHeight / 2), font: roomAreaFont,
                 color: .darkGray, background: .white)
        }
    }

    private static func drawFooter(_ document: FloorDocument, _ layout: PlanLayout, size: CGSize, in context: CGContext) {
        let y = size.height - margin - 22
        // A scale bar about a fifth of the page wide, in round feet.
        let footPoints = 0.3048 * layout.scale
        let feet = [1.0, 2, 5, 10, 20, 50, 100].last { $0 * footPoints <= size.width / 5 } ?? 1
        let barLength = feet * footPoints
        context.setStrokeColor(UIColor.black.cgColor)
        context.setLineWidth(1.5)
        context.strokeLineSegments(between: [
            CGPoint(x: margin, y: y), CGPoint(x: margin + barLength, y: y),
            CGPoint(x: margin, y: y - 3), CGPoint(x: margin, y: y + 3),
            CGPoint(x: margin + barLength, y: y - 3), CGPoint(x: margin + barLength, y: y + 3),
        ])
        text("\(Int(feet)) ft", at: CGPoint(x: margin + barLength + 6, y: y - 6), font: .systemFont(ofSize: 8), color: .black)

        var x = size.width - margin - 190
        for (label, color) in [("Wall", wallColor), ("Door", doorColor), ("Window", windowColor), ("Opening", openingColor)] {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(3)
            context.strokeLineSegments(between: [CGPoint(x: x, y: y), CGPoint(x: x + 12, y: y)])
            text(label, at: CGPoint(x: x + 15, y: y - 5), font: .systemFont(ofSize: 7.5), color: .darkGray)
            x += 48
        }

        let date = document.exportedAt.formatted(date: .abbreviated, time: .omitted)
        var note = "Scanned with iPhone LiDAR, \(date). Approximate: measure anything critical by hand. No north arrow: the scan has no compass reference."
        if document.mergeStatus == .unmerged { note = "Rooms not merged: shared walls may appear twice. " + note }
        text(note, at: CGPoint(x: margin, y: size.height - margin - 8), font: .systemFont(ofSize: 7), color: .darkGray)
    }

    private static func text(_ string: String, at point: CGPoint, font: UIFont, color: UIColor) {
        (string as NSString).draw(at: point, withAttributes: [.font: font, .foregroundColor: color])
    }

    private static func text(_ string: String, centeredAt point: CGPoint, font: UIFont, color: UIColor, background: UIColor = .clear) {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .backgroundColor: background]
        let size = (string as NSString).size(withAttributes: attributes)
        (string as NSString).draw(at: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), withAttributes: attributes)
    }
}
