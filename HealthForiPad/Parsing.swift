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
}

struct Job: Sendable {
    let name: String
    let path: (Date, Date) -> String
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
                Extractor(field: .awakeCount, keys: ["awakeCount"]),
                Extractor(field: .deepLo, keys: [], scale: 1.0 / 3600, path: ["sleepScores", "deepPercentage", "idealStartInSeconds"]),
                Extractor(field: .deepHi, keys: [], scale: 1.0 / 3600, path: ["sleepScores", "deepPercentage", "idealEndInSeconds"]),
                Extractor(field: .lightLo, keys: [], scale: 1.0 / 3600, path: ["sleepScores", "lightPercentage", "idealStartInSeconds"]),
                Extractor(field: .lightHi, keys: [], scale: 1.0 / 3600, path: ["sleepScores", "lightPercentage", "idealEndInSeconds"]),
                Extractor(field: .remLo, keys: [], scale: 1.0 / 3600, path: ["sleepScores", "remPercentage", "idealStartInSeconds"]),
                Extractor(field: .remHi, keys: [], scale: 1.0 / 3600, path: ["sleepScores", "remPercentage", "idealEndInSeconds"]),
                Extractor(field: .spo2Avg, keys: ["averageSpO2Value"]),
                Extractor(field: .spo2Low, keys: ["lowestSpO2Value"]),
                Extractor(field: .respAvg, keys: ["averageRespirationValue"]),
                Extractor(field: .sleepHR, keys: ["avgHeartRate"]),
                Extractor(field: .sleepStress, keys: ["avgSleepStress"]),
                Extractor(field: .sleepDeep, keys: ["deepSleepSeconds"], scale: 1.0 / 3600),
                Extractor(field: .sleepLight, keys: ["lightSleepSeconds"], scale: 1.0 / 3600),
                Extractor(field: .sleepRem, keys: ["remSleepSeconds"], scale: 1.0 / 3600),
                Extractor(field: .sleepAwake, keys: ["awakeSleepSeconds"], scale: 1.0 / 3600),
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

    static func records(_ any: Any, into out: inout [(Date, [String: Any])]) {
        if let d = any as? [String: Any] {
            for k in dateKeys {
                if let s = d[k] as? String, let date = Cal.parse(s) { out.append((date, d)); return }
            }
            for v in d.values { records(v, into: &out) }
        } else if let a = any as? [Any] {
            for v in a { records(v, into: &out) }
        }
    }

    static func numbers(_ any: Any, key: String, into out: inout [Double]) {
        if let d = any as? [String: Any] {
            for (k, v) in d {
                if k == key, let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { out.append(n.doubleValue) }
                else { numbers(v, key: key, into: &out) }
            }
        } else if let a = any as? [Any] {
            for v in a { numbers(v, key: key, into: &out) }
        }
    }

    static func parse(_ data: Data, job: Job) -> [Date: [Field: Double]] {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed) else { return [:] }
        var recs: [(Date, [String: Any])] = []
        records(json, into: &recs)
        var acc: [Date: [Field: [Double]]] = [:]
        for (date, rec) in recs {
            for ex in job.extractors {
                if !ex.path.isEmpty {
                    var cur: Any? = rec
                    for k in ex.path { cur = (cur as? [String: Any])?[k] }
                    if let n = cur as? NSNumber, n.doubleValue > 0 { acc[date, default: [:]][ex.field, default: []].append(n.doubleValue * ex.scale) }
                    continue
                }
                for key in ex.keys {
                    var nums: [Double] = []
                    numbers(rec, key: key, into: &nums)
                    nums = nums.filter { $0 > 0 }.map { v in
                        var x = v
                        if ex.gramsToKg && x > 400 { x /= 1000 }
                        return x * ex.scale
                    }
                    if !nums.isEmpty { acc[date, default: [:]][ex.field, default: []] += nums; break }
                }
            }
        }
        return acc.mapValues { $0.mapValues { $0.reduce(0, +) / Double($0.count) } }
    }
}


