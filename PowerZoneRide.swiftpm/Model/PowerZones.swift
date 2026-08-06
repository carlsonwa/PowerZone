import SwiftUI

/// The seven-zone model Peloton's Power Zone classes use, expressed as %FTP.
///
/// These bounds are what homefitnessbuddy's own target curve is built on — its Z1 blocks
/// sit at 45%, Z2 at 65%, Z3 at 83%, sweet spot at 90%, Z4 at 97%, Z5 at 107-112% — so
/// matching them here keeps the coloured bands aligned with the target blocks.
enum PowerZones {
    /// Upper bound of each zone as a fraction of FTP. Zone 7 is open-ended.
    static let upperBounds: [Double] = [0.55, 0.75, 0.90, 1.05, 1.20, 1.50]

    static func zone(forPercentFTP pct: Double) -> Int {
        for (i, bound) in upperBounds.enumerated() where pct <= bound * 100 {
            return i + 1
        }
        return 7
    }

    static func zone(forWatts watts: Double, ftp: Double) -> Int {
        guard ftp > 0 else { return 1 }
        return zone(forPercentFTP: watts / ftp * 100)
    }

    /// Watt range of a zone for a given FTP. Zone 7's top is nominal — it only exists so
    /// the chart has something finite to draw.
    static func wattRange(zone: Int, ftp: Double) -> ClosedRange<Double> {
        let lower = zone == 1 ? 0 : upperBounds[zone - 2] * ftp
        let upper = zone <= upperBounds.count ? upperBounds[zone - 1] * ftp : ftp * 2.0
        return lower...upper
    }

    /// Cool blues through to hot reds as effort climbs. Deliberately not Peloton's own
    /// palette — these are picked to stay distinguishable on a dimmed screen and to the
    /// most common forms of colour blindness.
    static func color(zone: Int) -> Color {
        switch zone {
        case 1: return Color(red: 0.42, green: 0.47, blue: 0.55)
        case 2: return Color(red: 0.20, green: 0.55, blue: 0.85)
        case 3: return Color(red: 0.15, green: 0.68, blue: 0.55)
        case 4: return Color(red: 0.95, green: 0.75, blue: 0.20)
        case 5: return Color(red: 0.95, green: 0.52, blue: 0.15)
        case 6: return Color(red: 0.88, green: 0.28, blue: 0.22)
        default: return Color(red: 0.72, green: 0.15, blue: 0.42)
        }
    }
}
