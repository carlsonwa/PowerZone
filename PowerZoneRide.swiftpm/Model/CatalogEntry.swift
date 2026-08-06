import Foundation

/// One row of the workout library table.
/// `Hashable` because the library pushes entries onto a `NavigationStack` path.
struct CatalogEntry: Identifiable, Equatable, Hashable, Codable {
    let id: Int
    let title: String       // "2026/03/31 @ 8:00AM ET"
    let airDate: String     // "2026-03-31"
    let instructor: String
    let minutes: Int
    let tss: Int
    let typeName: String    // "Power Zone Endurance (Rock)"
    let typeCode: String    // "PZE"
    let zones: String       // "Z1,Z2,Z3,Z4,Z5"

    /// What the library row shows: "45 min Power Zone Endurance".
    var summary: String { "\(minutes) min \(typeName)" }

    var zoneList: [String] {
        zones.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    var displayDate: String {
        guard airDate.count == 10 else { return airDate }
        let parts = airDate.split(separator: "-")
        guard parts.count == 3 else { return airDate }
        return "\(parts[1])/\(parts[2])/\(parts[0].suffix(2))"
    }
}
