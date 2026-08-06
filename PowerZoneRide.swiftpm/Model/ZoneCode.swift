import SwiftUI

/// A zone label as it appears in the third slot of homefitnessbuddy's `intervals` array.
///
/// The display names are taken from the site's own `updateBlock()` switch so the readout
/// on the bike matches what the website would have said at the same moment.
enum ZoneCode: Equatable, Hashable {
    case zone(Int)      // "1"..."7"
    case warmUp         // "WU"
    case coolDown       // "CD"
    case sweetSpot      // "SS"
    case spinUp         // "SU"
    case severalSpinUps // "SUA"
    case flatRoad       // "I"
    case end            // "END"
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "WU": self = .warmUp
        case "CD": self = .coolDown
        case "SS": self = .sweetSpot
        case "SU": self = .spinUp
        case "SUA": self = .severalSpinUps
        case "I": self = .flatRoad
        case "END": self = .end
        default:
            if let n = Int(rawValue), (1...7).contains(n) {
                self = .zone(n)
            } else {
                self = .unknown(rawValue)
            }
        }
    }

    var displayName: String {
        switch self {
        case .zone(let n): return "Zone \(n)"
        case .warmUp: return "Warm Up"
        case .coolDown: return "Cool Down"
        case .sweetSpot: return "Sweet Spot"
        case .spinUp: return "Spin-Up"
        case .severalSpinUps: return "Several Spin-Ups"
        case .flatRoad: return "Flat Road"
        case .end: return "Ride Completion"
        case .unknown(let s): return s
        }
    }

    /// Compact form for the interval strip, where horizontal space is tight.
    var shortName: String {
        switch self {
        case .zone(let n): return "Z\(n)"
        case .warmUp: return "WU"
        case .coolDown: return "CD"
        case .sweetSpot: return "SS"
        case .spinUp: return "SU"
        case .severalSpinUps: return "SU×"
        case .flatRoad: return "FLAT"
        case .end: return "END"
        case .unknown(let s): return s
        }
    }

    /// The numbered zone this block trains, for colouring. Named blocks map onto the
    /// zone they actually sit in: a spin-up is a Z3-ish effort, sweet spot is upper Z3.
    var colorZone: Int {
        switch self {
        case .zone(let n): return n
        case .warmUp, .flatRoad: return 1
        case .coolDown: return 1
        case .sweetSpot: return 3
        case .spinUp, .severalSpinUps: return 3
        case .end, .unknown: return 1
        }
    }
}
