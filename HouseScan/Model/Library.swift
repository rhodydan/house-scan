import Foundation

/// Everything the app knows, apart from the scan and photo files on disk. Saved as library.json.
struct Library: Codable, Equatable {
    var projects: [Project] = []
}

struct Project: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    var floors: [Floor] = []
    var siteNotes: [SiteNote] = []
}

struct Floor: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var rooms: [Room] = []
    /// The AR coordinate space of this floor's saved world map. Rooms only merge when they share a space.
    var spaceID: UUID?
}

struct Room: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var scan: ScanRecord?
    var items: [InventoryItem] = []
}

struct ScanRecord: Codable, Equatable {
    var scannedAt: Date
    var spaceID: UUID
}

/// Something in a room, recorded for insurance. Rooms don't have to be scanned to hold items.
struct InventoryItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var model = ""
    var notes = ""
    var serialNumber = ""
    /// Whole cents, so totals are exact.
    var valueCents: Int?
    /// File names in the photos folder.
    var photos: [String] = []
    /// Filled in from a label photo and not yet looked over in the editor.
    var needsChecking = false
}

extension InventoryItem {
    /// What was typed in the value box, in cents. Nil unless it is a plain amount, such as "$1,299.50".
    static func cents(typed: String) -> Int? {
        let amount = typed.filter { !"$, ".contains($0) }
        guard amount.range(of: #"^(\d+\.?\d*|\.\d+)$"#, options: .regularExpression) != nil,
              let dollars = Decimal(string: amount) else { return nil }
        return cents(dollars)
    }

    static func cents(_ dollars: Decimal) -> Int {
        let wholeCents = NSDecimalNumberHandler(roundingMode: .plain, scale: 0, raiseOnExactness: false, raiseOnOverflow: false,
                                                raiseOnUnderflow: false, raiseOnDivideByZero: false)
        return NSDecimalNumber(decimal: dollars * 100).rounding(accordingToBehavior: wholeCents).intValue
    }
}

// Files saved before phase 2 have no items or site notes.
extension Project {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        floors = try container.decode([Floor].self, forKey: .floors)
        siteNotes = try container.decodeIfPresent([SiteNote].self, forKey: .siteNotes) ?? []
    }
}

// Items saved before label scanning have no model and nothing to check.
extension InventoryItem {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? ""
        notes = try container.decode(String.self, forKey: .notes)
        serialNumber = try container.decode(String.self, forKey: .serialNumber)
        valueCents = try container.decodeIfPresent(Int.self, forKey: .valueCents)
        photos = try container.decode([String].self, forKey: .photos)
        needsChecking = try container.decodeIfPresent(Bool.self, forKey: .needsChecking) ?? false
    }
}

extension Room {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        scan = try container.decodeIfPresent(ScanRecord.self, forKey: .scan)
        items = try container.decodeIfPresent([InventoryItem].self, forKey: .items) ?? []
    }
}
