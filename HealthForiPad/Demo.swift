import Foundation

enum Demo {
    /// Deterministic synthetic data so the UI can be explored without a Garmin account.
    static func generate() -> [Date: DayPoint] {
        var out: [Date: DayPoint] = [:]
        let today = Cal.noon(Date())
        func noise(_ i: Int, _ seed: Double) -> Double { sin(Double(i) * 12.9898 + seed) * 43758.5453 .truncatingRemainder(dividingBy: 1) }
        for i in 0..<400 {
            let d = Cal.add(-i, to: today)
            var p = DayPoint(date: d)
            let t = Double(i)
            let wave = sin(t / 23)
            p.values[.rhr] = 56 + 3 * wave + 1.5 * sin(t * 1.7) + (i < 40 ? 1.5 : 0)
            p.values[.sleepHours] = max(4.5, 7.1 + 0.8 * sin(t / 5.5) + 0.5 * sin(t * 2.3))
            p.values[.sleepScore] = 78 + 8 * sin(t / 5.5)
            let total = p.values[.sleepHours] ?? 7
            let deep = total * (0.17 + 0.04 * sin(t * 1.3)), rem = total * (0.22 + 0.03 * sin(t * 0.9 + 1))
            p.values[.sleepDeep] = deep; p.values[.sleepRem] = rem
            p.values[.sleepLight] = total - deep - rem
            let wake = Cal.cal.startOfDay(for: d).addingTimeInterval(7 * 3600 + 600 * sin(t))
            let bed = wake.addingTimeInterval(-(total + 0.6) * 3600)
            let off = Double(TimeZone.current.secondsFromGMT(for: d))     // Garmin's "local" timestamps are wall-clock-as-UTC
            p.values[.sleepStart] = bed.timeIntervalSince1970 + off
            p.values[.sleepEnd] = wake.timeIntervalSince1970 + off
            p.values[.awakeCount] = 1 + (i % 3 == 0 ? 1 : 0)
            p.values[.deepLo] = 1.1; p.values[.deepHi] = 2.4
            p.values[.lightLo] = 2.4; p.values[.lightHi] = 5.0
            p.values[.remLo] = 1.5; p.values[.remHi] = 2.3
            p.values[.sleepAwake] = 0.3 + 0.25 * (1 + sin(t * 2.7))
            p.values[.spo2Avg] = 94 + 1.5 * sin(t / 6)
            p.values[.spo2Low] = 87 + 2.5 * sin(t * 1.3)
            p.values[.respAvg] = 15 + 1.2 * sin(t / 8)
            p.values[.sleepHR] = 58 + 3 * sin(t / 12) + 1.5 * sin(t * 2.2)
            p.values[.sleepStress] = 22 + 5 * sin(t / 7) + 2 * sin(t * 1.9)
            p.values[.stress] = 32 + 9 * sin(t / 9) + 4 * sin(t * 3.1)
            if i % 2 == 0 {
                p.values[.bodyFat] = 19.5 + 1.2 * sin(t / 30) + 0.4 * sin(t * 1.7)
                p.values[.muscleMass] = 35.2 + 0.6 * sin(t / 45) + 0.2 * sin(t * 2.1)
            }
            if i % 2 == 0 { p.values[.weight] = 81.5 + 1.8 * sin(t / 40) + 0.35 * sin(t * 1.3) - Double(400 - i) * 0.0015 }
            if i % 3 != 2 {
                p.values[.systolic] = 128 + 9 * sin(t / 11) + 4 * sin(t * 2.1)
                p.values[.diastolic] = 82 + 6 * sin(t / 11 + 1) + 2 * sin(t * 1.9)
                let spreadS = 5 + 4 * abs(sin(t * 1.3)), spreadD = 3 + 3 * abs(sin(t * 0.7))
                p.values[.sysMin] = p.values[.systolic]! - spreadS; p.values[.sysMax] = p.values[.systolic]! + spreadS * 1.3
                p.values[.diaMin] = p.values[.diastolic]! - spreadD; p.values[.diaMax] = p.values[.diastolic]! + spreadD * 1.3
            }
            _ = noise
            out[d] = p
        }
        return out
    }

    /// Individual readings for demo mode: 1–3 per day (morning / noon / evening) scattered around that day's average.
    static func readings(from days: [Date: DayPoint]) -> [BPReading] {
        var out: [BPReading] = []
        for p in days.values.sorted(by: { $0.date < $1.date }) {
            guard let s = p[.systolic], let d = p[.diastolic] else { continue }
            let n = 1 + (Int(p.date.timeIntervalSince1970 / 86400) % 3)
            for k in 0..<n {
                let jitterS = [-6.0, 2.0, 7.0][k] , jitterD = [-3.0, 1.0, 4.0][k]
                let hour = [7.5, 13.0, 20.25][k]
                let time = Cal.cal.startOfDay(for: p.date).addingTimeInterval(hour * 3600)
                out.append(BPReading(time: time, sys: s + jitterS, dia: d + jitterD))
            }
        }
        return out
    }
}
