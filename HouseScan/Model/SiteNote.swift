import CoreLocation
import Foundation

/// A photo with where it was taken, which way the phone faced, and a note.
struct SiteNote: Codable, Identifiable, Equatable {
    var id = UUID()
    var takenAt: Date
    var note: String
    /// File name in the photos folder.
    var photo: String
    var position: SitePosition?
    var heading: SiteHeading?
}

/// What Core Location reported. The accuracy is its own estimate, not a measurement.
struct SitePosition: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    /// Apple's "radius of uncertainty", in metres.
    var horizontalAccuracy: Double
    /// Metres above sea level, when valid.
    var altitude: Double?
    var verticalAccuracy: Double?
    /// How old the fix was when the photo was taken.
    var fixAgeSeconds: Double
    /// False when Precise Location is off, which blurs the position by design.
    var isPrecise: Bool
}

struct SiteHeading: Codable, Equatable {
    /// Degrees from true north, when iOS could work it out.
    var trueDegrees: Double?
    var magneticDegrees: Double
    /// Apple's "maximum deviation" in degrees, when valid.
    var accuracyDegrees: Double?
}

extension SitePosition {
    /// Nil when Core Location says the fix is invalid, which it signals with a negative accuracy.
    init?(_ location: CLLocation, at time: Date, isPrecise: Bool) {
        guard location.horizontalAccuracy >= 0 else { return nil }
        let hasAltitude = location.verticalAccuracy > 0
        self.init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                  horizontalAccuracy: location.horizontalAccuracy, altitude: hasAltitude ? location.altitude : nil,
                  verticalAccuracy: hasAltitude ? location.verticalAccuracy : nil,
                  fixAgeSeconds: max(0, time.timeIntervalSince(location.timestamp)), isPrecise: isPrecise)
    }
}

extension SiteHeading {
    /// Nil when the heading is invalid: an uncalibrated compass or strong magnetic interference.
    init?(magnetic: Double, true trueDegrees: Double, accuracy: Double) {
        guard accuracy >= 0, magnetic >= 0 else { return nil }
        self.init(trueDegrees: trueDegrees >= 0 ? trueDegrees : nil, magneticDegrees: magnetic, accuracyDegrees: accuracy)
    }
}

/// Plain-language labels. They only ever describe a phone's estimate, and always say so.
enum SiteLabel {
    /// A fix older than this is probably not where the phone is now.
    static let staleAfterSeconds = 15.0

    static func position(_ position: SitePosition?) -> String {
        guard let position else { return "No GPS position. Not survey-grade." }
        if !position.isPrecise {
            return "Approximate only: Precise Location is off. Not survey-grade."
        }
        let metres = Int(position.horizontalAccuracy.rounded())
        var label = "Phone estimate, within about \(metres) m (\(Int((position.horizontalAccuracy * 3.28084).rounded())) ft): \(grade(position.horizontalAccuracy))."
        if position.fixAgeSeconds > staleAfterSeconds {
            label += " Fix was \(Int(position.fixAgeSeconds)) s old."
        }
        return label + " Not survey-grade."
    }

    private static func grade(_ metres: Double) -> String {
        switch metres {
        case ..<6: "good for a phone"
        case ..<20: "fair"
        case ..<70: "poor"
        default: "very poor"
        }
    }

    static func heading(_ heading: SiteHeading?) -> String {
        guard let heading else { return "No compass heading." }
        let degrees = heading.trueDegrees ?? heading.magneticDegrees
        let north = heading.trueDegrees == nil ? "magnetic" : "true"
        var label = "\(Int(degrees.rounded()) % 360)° \(compassPoint(degrees)) (\(north))"
        if let accuracy = heading.accuracyDegrees {
            label += ", within about \(Int(accuracy.rounded()))°"
        }
        return label + ". Compass readings drift near metal and indoors."
    }

    static func compassPoint(_ degrees: Double) -> String {
        let points = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        return points[Int((degrees / 45).rounded()) % 8]
    }
}
