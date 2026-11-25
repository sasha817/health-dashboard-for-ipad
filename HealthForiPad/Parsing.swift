import Foundation

/// The Personal API's response shapes are not documented, so parsing is deliberately tolerant:
/// find per-day records (any dict carrying a date key) and average every numeric value found
/// under the candidate key names.
struct Extractor: Sendable {
    let field: Field
    let keys: [String]
    var scale: Double = 1
    var gramsToKg = false
    var path: [String] = []        // exact key path inside the day record (for nested values such as sleepScores.overall.value)
    var allowZero = false          // 0 is a real value here (0 awakenings, 0 h of deep sleep); otherwise 0 / negative means "no data"
}

struct Job: Sendable {
    let name: String
    let path: @Sendable (Date, Date) -> String
    let query: [String: String]
    let extractors: [Extractor]
}

enum Parsing {
    static let dateKeys = ["calendarDate", "summaryDate", "sleepDate", "date"]

    static func jobs() -> [Job] {
        func p(_ s: String) -> (Date, Date) -> String { { a, b in s.replacingOccurrences(of: "{a}", with: Cal.iso(a)).replacingOccurrences(of: "{b}", with: Cal.iso(b)) } }
        return [
            Job(name: "Daily summaries", path: { _, _ in "/usersummary-service/v2/dailysummaries" },
                query: [:], extractors: [
                    Extractor(field: .rhr, keys: ["restingValue", "restingHeartRate"]),
                    Extractor(field: .stress, keys: ["avgLevel", "averageStressLevel"]),
                ]),
            Job(name: "Sleep", path: { _, _ in "/sleep-service/sleep/dailySleepSummariesByDate" }, query: [:], extractors: [
                Extractor(field: .sleepHours, keys: ["sleepTimeSeconds", "totalSleepSeconds", "sleepSeconds"], scale: 1.0 / 3600),
                Extractor(field: .sleepScore, keys: [], path: ["sleepScores", "overall", "value"]),
                Extractor(field: .sleepStart, keys: ["sleepStartTimestampLocal"], scale: 0.001),
                Extractor(field: .sleepEnd, keys: ["sleepEndTimestampLocal"], scale: 0.001),
                Extractor(field: .awakeCount, keys: ["awakeCount"], allowZero: true),
                Extractor(field: .deepLo, keys: [], scale: 1.0 / 3600, path: ["sleepScores", "deepPercentage", "idealStartInSeconds"], allowZero: true),
                Extractor(field: .deepHi, keys: [], scale: 1.0 / 3600, path: ["sleepScores", "deepPercentage", "idealEndInSeconds"], allowZero: true),
                Extractor(field: .lightLo, keys: [], scale: 1.0 / 3600, path: ["sleepScores", "lightPercentage", "idealStartInSeconds"], allowZero: true),
                Extractor(field: .lightHi, keys: [], scale: 1.0 / 3600, path: ["sleepScores", "lightPercentage", "idealEndInSeconds"], allowZero: true),
                Extractor(field: .remLo, keys: [], scale: 1.0 / 3600, path: ["sleepScores", "remPercentage", "idealStartInSeconds"], allowZero: true),
                Extractor(field: .remHi, keys: [], scale: 1.0 / 3600, path: ["sleepScores", "remPercentage", "idealEndInSeconds"], allowZero: true),
                Extractor(field: .spo2Avg, keys: ["averageSpO2Value"]),
                Extractor(field: .spo2Low, keys: ["lowestSpO2Value"]),
                Extractor(field: .respAvg, keys: ["averageRespirationValue"]),
                Extractor(field: .sleepHR, keys: ["avgHeartRate"]),
                Extractor(field: .sleepStress, keys: ["avgSleepStress"]),
                Extractor(field: .sleepDeep, keys: ["deepSleepSeconds"], scale: 1.0 / 3600, allowZero: true),
                Extractor(field: .sleepLight, keys: ["lightSleepSeconds"], scale: 1.0 / 3600, allowZero: true),
                Extractor(field: .sleepRem, keys: ["remSleepSeconds"], scale: 1.0 / 3600, allowZero: true),
                Extractor(field: .sleepAwake, keys: ["awakeSleepSeconds"], scale: 1.0 / 3600, allowZero: true),
            ]),
            Job(name: "Weight", path: p("/weight-service/weight/range/{a}/{b}"), query: ["includeAll": "true"], extractors: [
                Extractor(field: .weight, keys: ["weight"], gramsToKg: true),
                Extractor(field: .bodyFat, keys: ["bodyFat"]),
                Extractor(field: .muscleMass, keys: ["muscleMass"], gramsToKg: true),
            ]),
        ]
    }

    /// Jobs whose endpoints take start/end as query params rather than path segments.
    static func query(for job: Job, from: Date, to: Date) -> [String: String] {
        var q = job.query
        if job.name == "Daily summaries" || job.name == "Sleep" {
            q["startDate"] = Cal.iso(from); q["endDate"] = Cal.iso(to)
        }
        return q
    }

    static func datedRecord(_ d: [String: Any]) -> Date? {
        for k in dateKeys { if let s = d[k] as? String, let date = Cal.parse(s) { return date } }
        return nil
    }

    /// A dict that carries a date but also holds an array of dated dicts is a *wrapper* (e.g. a weight summary
    /// containing its individual measurements), not a record itself: its children are the records.
    private static func hasDatedChildren(_ d: [String: Any]) -> Bool {
        for v in d.values {
            guard let arr = v as? [Any] else { continue }
            for e in arr { if let ed = e as? [String: Any], datedRecord(ed) != nil { return true } }
        }
        return false
    }

    static func records(_ any: Any, into out: inout [(Date, [String: Any])]) {
        if let d = any as? [String: Any] {
            if let date = datedRecord(d), !hasDatedChildren(d) { out.append((date, d)); return }
            for v in d.values { records(v, into: &out) }
        } else if let a = any as? [Any] {
            for v in a { records(v, into: &out) }
        }
    }

    /// All numbers stored under `key` anywhere inside `any`, with their nesting depth.
    static func numbers(_ any: Any, key: String, depth: Int = 0, into out: inout [(depth: Int, value: Double)]) {
        if let d = any as? [String: Any] {
            for (k, v) in d {
                if k == key, let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { out.append((depth, n.doubleValue)) }
                else { numbers(v, key: key, depth: depth + 1, into: &out) }
            }
        } else if let a = any as? [Any] {
            for v in a { numbers(v, key: key, depth: depth, into: &out) }
        }
    }

    /// True for any well-formed JSON document (including `null` for "no content"); false for empty or non-JSON bodies.
    static func isValidPayload(_ data: Data) -> Bool {
        !data.isEmpty && (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) != nil
    }

    static func parse(_ data: Data, job: Job) -> [Date: [Field: Double]] {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { return [:] }
        var recs: [(Date, [String: Any])] = []
        records(json, into: &recs)
        var acc: [Date: [Field: [Double]]] = [:]
        func keep(_ v: Double, _ ex: Extractor) -> Bool { ex.allowZero ? v >= 0 : v > 0 }
        for (date, rec) in recs {
            for ex in job.extractors {
                if !ex.path.isEmpty {
                    var cur: Any? = rec
                    for k in ex.path { cur = (cur as? [String: Any])?[k] }
                    if let n = cur as? NSNumber, keep(n.doubleValue, ex) { acc[date, default: [:]][ex.field, default: []].append(n.doubleValue * ex.scale) }
                    continue
                }
                for key in ex.keys {
                    var found: [(depth: Int, value: Double)] = []
                    numbers(rec, key: key, into: &found)
                    // the same key can also appear in nested objects (e.g. an `avgHeartRate` inside `sleepMovement`):
                    // only the shallowest occurrences belong to this record
                    guard let shallowest = found.map(\.depth).min() else { continue }
                    let nums = found.filter { $0.depth == shallowest && keep($0.value, ex) }.map { f -> Double in
                        var x = f.value
                        if ex.gramsToKg && x > 400 { x /= 1000 }
                        return x * ex.scale
                    }
                    if !nums.isEmpty { acc[date, default: [:]][ex.field, default: []] += nums; break }
                }
            }
        }
        // The same measurement can be listed more than once in a response (e.g. as "latest" and inside "all"):
        // identical values on the same day count once.
        return acc.mapValues { fields in
            fields.mapValues { vals in
                var uniq: [Double] = []
                for v in vals where !uniq.contains(where: { abs($0 - v) < 1e-6 }) { uniq.append(v) }
                return uniq.reduce(0, +) / Double(uniq.count)
            }
        }
    }
}
