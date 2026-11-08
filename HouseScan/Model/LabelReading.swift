import Foundation

/// The make, model and serial number in the text of a rating or serial label. OCR misreads characters, so every
/// item made from one keeps the label photo and is marked for checking.
struct LabelReading: Equatable, Sendable {
    var make = ""
    var model = ""
    var serial = ""

    var isEmpty: Bool { model.isEmpty && serial.isEmpty }

    init(make: String = "", model: String = "", serial: String = "") {
        self.make = make
        self.model = model
        self.serial = serial
    }

    /// `lines` in reading order. `barcodes` are the payloads of any linear or Data Matrix codes on the label.
    init(lines: [String], barcodes: [String] = []) {
        var pending: [Field] = []
        for line in lines {
            let matches = Self.keyword.matches(in: line, range: NSRange(line.startIndex..., in: line))
            guard !matches.isEmpty else {
                // A keyword on one line and its value alone on a later one, as in stacked or side-by-side layouts.
                let tokens = line.split(whereSeparator: \.isWhitespace)
                if tokens.count == 1, let value = Self.value(tokens[0]), !pending.isEmpty {
                    set(pending.removeFirst(), value)
                }
                continue
            }
            for (index, match) in matches.enumerated() {
                let field: Field = match.range(at: 1).location != NSNotFound ? .model : .serial
                let start = match.range.upperBound
                let end = index + 1 < matches.count ? matches[index + 1].range.location : (line as NSString).length
                let rest = (line as NSString).substring(with: NSRange(location: start, length: end - start))
                if let value = rest.split(whereSeparator: \.isWhitespace).lazy.compactMap(Self.trimmed).first.flatMap(Self.value) {
                    set(field, value)
                } else {
                    pending.append(field)
                }
            }
        }

        // A barcode is exact where OCR guesses, so it wins when the two differ only by look-alike characters.
        let codes = barcodes.compactMap { Self.value(Substring($0)) }
        if let code = codes.first(where: { Self.lookAlike($0, model) }) { model = code }
        if let code = codes.first(where: { Self.lookAlike($0, serial) }) { serial = code }
        let spare = codes.filter { $0 != model && $0 != serial }
        if serial.isEmpty, spare.count == 1 { serial = spare[0] }

        make = lines.lazy.compactMap(Self.brand).first ?? ""
    }

    private enum Field { case model, serial }

    private mutating func set(_ field: Field, _ value: String) {
        switch field {
        case .model where model.isEmpty: model = value
        case .serial where serial.isEmpty: serial = value
        default: break
        }
    }

    /// Group 1 is a model keyword, group 2 a serial one. "SIN" is how OCR often reads "S/N".
    private static let keyword = try! NSRegularExpression(
        pattern: #"(?<![A-Z0-9])(?:(MODEL(?:\s*(?:NUMBER|NO\.?|#))?|MOD(?:\.?\s*NO\.?|\.)|M/N)|"#
            + #"(SERIAL(?:\s*(?:NUMBER|NO\.?|#))?|SER(?:\.?\s*NO\.?|\.)|S[/|I1]N(?=\s*[:#.=-])|SN(?=\s*[:#.=-])))(?![A-Z])"#,
        options: .caseInsensitive)

    private static func trimmed(_ token: Substring) -> Substring? {
        let token = token.trimmingCharacters(in: CharacterSet(charactersIn: ":#.=-_,;"))
        return token.isEmpty ? nil : Substring(token)
    }

    /// Model and serial numbers are letters and digits with a digit somewhere, and aren't ratings like 120V or 60Hz.
    private static func value(_ token: Substring) -> String? {
        guard let token = trimmed(token), token.count >= 3,
              token.allSatisfy({ $0.isLetter || $0.isNumber || "-./".contains($0) }),
              token.contains(where: \.isNumber),
              token.range(of: #"^\d+(\.\d+)?(V|VAC|W|KW|A|MA|HZ)$"#, options: [.regularExpression, .caseInsensitive]) == nil
        else { return nil }
        return String(token)
    }

    private static func lookAlike(_ a: String, _ b: String) -> Bool {
        func plain(_ s: String) -> String {
            String(s.uppercased().map { ["O": "0", "I": "1", "L": "1", "S": "5", "B": "8", "Z": "2"][$0] ?? $0 })
        }
        return !b.isEmpty && a != b && plain(a) == plain(b)
    }

    private static let brands = [
        "Samsung", "LG", "Whirlpool", "GE", "Maytag", "KitchenAid", "Bosch", "Frigidaire", "Kenmore", "Electrolux",
        "Miele", "Sub-Zero", "Thermador", "Viking", "Wolf", "Speed Queen", "Amana", "Haier", "Sony", "Panasonic",
        "Vizio", "TCL", "Hisense", "Sharp", "Apple", "Dell", "Lenovo", "Canon", "Nikon", "Epson", "Dyson", "iRobot",
        "Breville", "Bose", "Sonos", "Yamaha", "Denon", "Trane", "Carrier", "Lennox", "Rheem", "Rinnai", "Navien",
        "A.O. Smith", "Generac", "Toro", "Honda", "Craftsman", "DeWalt", "Milwaukee", "Makita", "Nintendo", "Microsoft",
    ]

    private static func brand(in line: String) -> String? {
        brands.first { line.range(of: "(?<![A-Za-z])\(NSRegularExpression.escapedPattern(for: $0))(?![A-Za-z])",
                                  options: [.regularExpression, .caseInsensitive]) != nil }
    }
}

extension InventoryItem {
    /// An item made from a label photo, named for what the label says.
    init(reading: LabelReading, photo: String) {
        let name = [reading.make, reading.model].filter { !$0.isEmpty }.joined(separator: " ")
        self.init(name: name.isEmpty ? "Label photo" : name, model: reading.model, serialNumber: reading.serial,
                  photos: [photo], needsChecking: true)
    }
}
