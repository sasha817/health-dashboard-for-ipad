import Foundation

enum Field: String, CaseIterable, Hashable, Sendable {
    case rhr, rhrAvg, sleepStart, sleepEnd, awakeCount, deepLo, deepHi, lightLo, lightHi, remLo, remHi, spo2Avg, spo2Low, respAvg, sleepHR, sleepStress, bodyFat, muscleMass, weightTrend, fatMassTrend, leanMassTrend, muscleTrend, sleepHours, sleepScore, sleepDeep, sleepLight, sleepRem, sleepAwake, systolic, diastolic, weight, stress

    var label: String {
        switch self {
        case .rhr: "Resting HR"
        case .sleepStart: "Bedtime"
        case .sleepEnd: "Wake-up"
        case .awakeCount: "Awakenings"
        case .deepLo, .deepHi, .lightLo, .lightHi, .remLo, .remHi: "Ideal range"
        case .rhrAvg: "Rolling avg"
        case .weightTrend, .fatMassTrend, .leanMassTrend, .muscleTrend: "Trend"
        case .spo2Avg: "SpO₂ avg"
        case .spo2Low: "SpO₂ lowest"
        case .respAvg: "Respiration"
        case .sleepHR: "Heart rate"
        case .sleepStress: "Stress"
        case .bodyFat: "Body fat"
        case .muscleMass: "Muscle"
        case .sleepHours: "Sleep"
        case .sleepDeep: "Deep"
        case .sleepLight: "Light"
        case .sleepRem: "REM"
        case .sleepAwake: "Awake"
        case .sleepScore: "Sleep score"
        case .systolic: "Systolic"
        case .diastolic: "Diastolic"
        case .weight: "Weight"
        case .stress: "Stress"
        }
    }

    var unit: String {
        switch self {
        case .rhr, .rhrAvg: "bpm"
        case .sleepStart, .sleepEnd, .awakeCount: ""
        case .deepLo, .deepHi, .lightLo, .lightHi, .remLo, .remHi: "h"
        case .bodyFat, .spo2Avg, .spo2Low: "%"
        case .respAvg: "/min"
        case .sleepHR: "bpm"
        case .muscleMass, .weightTrend, .fatMassTrend, .leanMassTrend, .muscleTrend: "kg"
        case .sleepHours, .sleepDeep, .sleepLight, .sleepRem, .sleepAwake: "h"
        case .sleepScore, .stress, .sleepStress: ""
        case .systolic, .diastolic: "mmHg"
        case .weight: "kg"
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .sleepHours, .sleepDeep, .sleepLight, .sleepRem, .sleepAwake, .deepLo, .deepHi, .lightLo, .lightHi, .remLo, .remHi:
            let m = Int((v * 60).rounded())
            return "\(m / 60)h \(String(format: "%02d", m % 60))m"
        case .weight, .muscleMass, .weightTrend, .fatMassTrend, .leanMassTrend, .muscleTrend: return String(format: "%.1f kg", v)
        case .bodyFat: return String(format: "%.1f %%", v)
        case .spo2Avg, .spo2Low: return String(format: "%.0f %%", v)
        case .respAvg: return String(format: "%.0f /min", v)
        case .sleepHR: return String(format: "%.0f bpm", v)
        case .rhr: return String(format: "%.0f bpm", v)
        case .sleepStart, .sleepEnd, .awakeCount: return String(format: "%.0f", v)
        case .rhrAvg: return String(format: "%.1f bpm", v)
        case .systolic, .diastolic: return String(format: "%.0f", v)
        case .sleepScore, .stress, .sleepStress: return String(format: "%.0f", v)
        }
    }
}

struct DayPoint: Identifiable, Sendable {
    let date: Date            // always noon local time
    var values: [Field: Double] = [:]
    var id: Date { date }
    subscript(f: Field) -> Double? { values[f] }
}

enum TimeRange: Int, CaseIterable, Identifiable {
    case week = 7, month = 30, quarter = 90, half = 180, year = 365, twoYears = 730
    var id: Int { rawValue }
    var days: Int { rawValue }
    var label: String {
        switch self {
        case .week: "7 days"
        case .month: "30 days"
        case .quarter: "90 days"
        case .half: "180 days"
        case .year: "1 year"
        case .twoYears: "2 years"
        }
    }
    var short: String {
        switch self {
        case .week: "1W"
        case .month: "30D"
        case .quarter: "90D"
        case .half: "180D"
        case .year: "1Y"
        case .twoYears: "2Y"
        }
    }
}

enum Cal {
    static var cal: Calendar { Calendar.current }
    static func noon(_ d: Date) -> Date {
        cal.date(bySettingHour: 12, minute: 0, second: 0, of: cal.startOfDay(for: d))!
    }
    static func add(_ days: Int, to d: Date) -> Date { cal.date(byAdding: .day, value: days, to: d)! }
    static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    static func iso(_ d: Date) -> String { isoFormatter.string(from: d) }
    static func parse(_ s: String) -> Date? {
        guard s.count >= 10 else { return nil }
        return isoFormatter.date(from: String(s.prefix(10))).map(noon)
    }
}


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
    /// Diastolic limits are drawn between 0–100 mmHg, systolic limits above 100, so one axis can carry both.
    var zones: [Zone] {
        switch self {
        case .aha: [
            Zone(from: 0, to: 80, color: .green), Zone(from: 80, to: 90, color: .orange), Zone(from: 90, to: 100, color: .red),
            Zone(from: 100, to: 120, color: .green), Zone(from: 120, to: 130, color: .yellow),
            Zone(from: 130, to: 140, color: .orange), Zone(from: 140, to: 400, color: .red)]
        case .esc: [
            Zone(from: 0, to: 85, color: .green), Zone(from: 85, to: 90, color: .yellow), Zone(from: 90, to: 100, color: .orange),
            Zone(from: 100, to: 130, color: .green), Zone(from: 130, to: 140, color: .yellow),
            Zone(from: 140, to: 160, color: .orange), Zone(from: 160, to: 400, color: .red)]
        }
    }
}
