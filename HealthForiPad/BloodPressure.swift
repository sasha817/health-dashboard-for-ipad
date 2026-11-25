import SwiftUI

/// Blood-pressure categories. Systolic and diastolic have *different* limits, and a reading is classified by the
/// worse of the two, so they are handled separately everywhere (no shared axis with mixed bands).
enum BPGuideline: String, CaseIterable, Identifiable {
    case aha, esc
    var id: String { rawValue }
    var label: String { self == .aha ? "AHA / ACC 2017" : "ESC / ESH 2018" }
    var legend: String {
        switch self {
        case .aha: "Zones (AHA): green normal · yellow elevated · orange stage 1 · red stage 2"
        case .esc: "Zones (ESC): green optimal/normal · yellow high-normal · orange grade 1 · red grade 2–3"
        }
    }
    var categoryNames: [String] {
        self == .aha ? ["Normal", "Elevated", "Stage 1", "Stage 2"] : ["Normal", "High-normal", "Grade 1", "Grade 2+"]
    }

    /// Upper limits (exclusive) of categories 0…2; anything at or above the last limit is category 3.
    /// AHA has no "elevated" band for diastolic, so its first two limits are equal.
    var sysLimits: [Double] { self == .aha ? [120, 130, 140] : [130, 140, 160] }
    var diaLimits: [Double] { self == .aha ? [80, 80, 90] : [85, 90, 100] }

    func sysCategory(_ v: Double) -> Int { sysLimits.firstIndex { v < $0 } ?? 3 }
    func diaCategory(_ v: Double) -> Int { diaLimits.firstIndex { v < $0 } ?? 3 }
    /// A reading is as bad as the worse of its two numbers.
    func category(sys: Double, dia: Double) -> Int { max(sysCategory(sys), diaCategory(dia)) }

    static let zoneColors: [Color] = [.green, .yellow, .orange, .red]
    /// Stronger colours for markers on top of the pale zone bands.
    static let markerColors: [Color] = [Color(red: 0.12, green: 0.6, blue: 0.25), Color(red: 0.85, green: 0.62, blue: 0.0), .orange, .red]

    var sysZones: [Zone] { Self.zones(limits: sysLimits) }
    var diaZones: [Zone] { Self.zones(limits: diaLimits) }

    private static func zones(limits: [Double]) -> [Zone] {
        var out: [Zone] = []
        var lo = 0.0
        for (i, up) in (limits + [400]).enumerated() {
            if up > lo { out.append(Zone(from: lo, to: up, color: zoneColors[i])) }
            lo = max(lo, up)
        }
        return out
    }
}

/// One blood-pressure measurement (a sys/dia pair taken at one moment).
struct BPReading: Identifiable, Sendable {
    let id = UUID()
    let time: Date
    let sys: Double
    let dia: Double
    var day: Date { Cal.noon(time) }
}
