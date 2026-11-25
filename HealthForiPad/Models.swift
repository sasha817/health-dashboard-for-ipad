import Foundation

enum Field: String, CaseIterable, Hashable, Sendable {
    case rhr, rhrAvg, sysMin, sysMax, diaMin, diaMax, sleepStart, sleepEnd, awakeCount, deepLo, deepHi, lightLo, lightHi, remLo, remHi, spo2Avg, spo2Low, respAvg, sleepHR, sleepStress, bodyFat, muscleMass, weightTrend, fatMassTrend, leanMassTrend, muscleTrend, sleepHours, sleepScore, sleepDeep, sleepLight, sleepRem, sleepAwake, systolic, diastolic, weight, stress, activeKcal, restingKcal, steps, moderateMin, vigorousMin

    var label: String {
        switch self {
        case .rhr: "Resting HR"
        case .sysMin, .sysMax: "Systolic range"
        case .diaMin, .diaMax: "Diastolic range"
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
        case .activeKcal: "Active calories"
        case .restingKcal: "Resting calories"
        case .steps: "Steps"
        case .moderateMin: "Moderate minutes"
        case .vigorousMin: "Vigorous minutes"
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
        case .systolic, .diastolic, .sysMin, .sysMax, .diaMin, .diaMax: "mmHg"
        case .weight: "kg"
        case .activeKcal, .restingKcal: "kcal"
        case .steps: ""
        case .moderateMin, .vigorousMin: "min"
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
        case .systolic, .diastolic, .sysMin, .sysMax, .diaMin, .diaMax: return String(format: "%.0f", v)
        case .sleepScore, .stress, .sleepStress: return String(format: "%.0f", v)
        case .activeKcal, .restingKcal: return String(format: "%.0f kcal", v)
        case .steps: return String(format: "%.0f", v)
        case .moderateMin, .vigorousMin: return String(format: "%.0f min", v)
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
        f.calendar = Calendar(identifier: .gregorian)       // never a Buddhist/Japanese calendar year
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
    /// Calendar dates ("2026-11-23") are the identity of a day; the noon `Date` is derived from them in the current time zone.
    static func iso(_ d: Date) -> String { isoFormatter.timeZone = .current; return isoFormatter.string(from: d) }
    static func parse(_ s: String) -> Date? {
        guard s.count >= 10 else { return nil }
        isoFormatter.timeZone = .current
        return isoFormatter.date(from: String(s.prefix(10))).map(noon)
    }
}

extension TimeRange {
    /// X-axis tick spacing and label format for a range (shared by all charts).
    var axisStride: (Calendar.Component, Int, Date.FormatStyle) {
        switch self {
        case .week: (.day, 1, .dateTime.weekday(.abbreviated))
        case .month: (.day, 7, .dateTime.day().month(.abbreviated))
        case .quarter: (.day, 14, .dateTime.day().month(.abbreviated))
        case .half: (.month, 1, .dateTime.month(.abbreviated))
        case .year: (.month, 2, .dateTime.month(.abbreviated))
        case .twoYears: (.month, 4, .dateTime.month(.abbreviated).year(.twoDigits))
        }
    }
}

extension Date {
    /// "Monday, 23-Nov-26"
    var shortDayLabel: String {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEE")
        let wd = f.string(from: self)
        f.dateFormat = "dd-MMM-yy"
        return "\(wd), \(f.string(from: self))"
    }
}
