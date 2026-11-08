import Foundation

/// Site notes as a CSV, with each photo copied beside it under the name the CSV gives.
enum SiteNotesCSV {
    static let header = [
        "taken_at_utc", "note", "photo_file", "latitude", "longitude", "horizontal_accuracy_m", "altitude_m",
        "vertical_accuracy_m", "fix_age_s", "precise_location", "heading_true_deg", "heading_magnetic_deg",
        "heading_accuracy_deg", "position_label", "heading_label",
    ]

    static func exportName(_ note: SiteNote, index: Int) -> String {
        String(format: "site-note-%03d.jpg", index + 1)
    }

    static func make(_ notes: [SiteNote]) -> String {
        let rows = notes.enumerated().map { index, note in row(note, photoFile: exportName(note, index: index)) }
        return ([header] + rows).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\r\n") + "\r\n"
    }

    private static func row(_ note: SiteNote, photoFile: String) -> [String] {
        let position = note.position
        let heading = note.heading
        return [
            note.takenAt.ISO8601Format(),
            note.note,
            photoFile,
            number(position?.latitude, places: 6),
            number(position?.longitude, places: 6),
            number(position?.horizontalAccuracy, places: 1),
            number(position?.altitude, places: 1),
            number(position?.verticalAccuracy, places: 1),
            number(position?.fixAgeSeconds, places: 0),
            position.map { $0.isPrecise ? "yes" : "no" } ?? "",
            number(heading?.trueDegrees, places: 1),
            number(heading?.magneticDegrees, places: 1),
            number(heading?.accuracyDegrees, places: 1),
            SiteLabel.position(position),
            SiteLabel.heading(heading),
        ]
    }

    private static func number(_ value: Double?, places: Int) -> String {
        value.map { String(format: "%.\(places)f", $0) } ?? ""
    }

    /// RFC 4180: quote a field holding a comma, quote or line break, and double any quotes inside.
    private static func escape(_ field: String) -> String {
        guard field.contains(where: { ",\"\r\n".contains($0) }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Writes the CSV and photos, and returns them in that order.
    static func export(_ notes: [SiteNote], project: String, files: ScanFiles, to directory: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let csv = directory.appending(path: "\(FloorExporter.fileName(project))-site-notes.csv")
        try Data(make(notes).utf8).write(to: csv, options: .atomic)
        var urls = [csv]
        for (index, note) in notes.enumerated() {
            let destination = directory.appending(path: exportName(note, index: index))
            try FileManager.default.copyItem(at: files.photoFile(note.photo), to: destination)
            urls.append(destination)
        }
        return urls
    }
}
