import Foundation
import HealthKit

enum HealthKitBP {
    private static let store = HKHealthStore()
    static var available: Bool { HKHealthStore.isHealthDataAvailable() }

    private static var sys: HKQuantityType { HKQuantityType(.bloodPressureSystolic) }
    private static var dia: HKQuantityType { HKQuantityType(.bloodPressureDiastolic) }

    static func requestAccess() async throws {
        try await store.requestAuthorization(toShare: [], read: [sys, dia])
    }

    private struct Daily { var avg: Double, min: Double, max: Double }

    /// Daily average and lowest/highest reading of systolic and diastolic, keyed by noon-of-day.
    static func fetch(from: Date, to: Date) async -> [Date: [Field: Double]] {
        async let s = daily(sys, from, to)
        async let d = daily(dia, from, to)
        var out: [Date: [Field: Double]] = [:]
        for (date, v) in await s { out[date, default: [:]][.systolic] = v.avg; out[date, default: [:]][.sysMin] = v.min; out[date, default: [:]][.sysMax] = v.max }
        for (date, v) in await d { out[date, default: [:]][.diastolic] = v.avg; out[date, default: [:]][.diaMin] = v.min; out[date, default: [:]][.diaMax] = v.max }
        return out
    }

    private static func daily(_ type: HKQuantityType, _ from: Date, _ to: Date) async -> [Date: Daily] {
        let start = Cal.cal.startOfDay(for: from)
        let end = Cal.add(1, to: Cal.cal.startOfDay(for: to))
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: pred,
                                                options: [.discreteAverage, .discreteMin, .discreteMax], anchorDate: start,
                                                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, results, _ in
                var out: [Date: Daily] = [:]
                let unit = HKUnit.millimeterOfMercury()
                results?.enumerateStatistics(from: start, to: end) { stat, _ in
                    if let a = stat.averageQuantity()?.doubleValue(for: unit) {
                        out[Cal.noon(stat.startDate)] = Daily(avg: a,
                            min: stat.minimumQuantity()?.doubleValue(for: unit) ?? a,
                            max: stat.maximumQuantity()?.doubleValue(for: unit) ?? a)
                    }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }

    /// Every individual measurement in the range (a cuff stores systolic + diastolic as one correlation).
    static func readings(from: Date, to: Date) async -> [BPReading] {
        let start = Cal.cal.startOfDay(for: from)
        let end = Cal.add(1, to: Cal.cal.startOfDay(for: to))
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKCorrelationQuery(type: HKCorrelationType(.bloodPressure), predicate: pred, samplePredicates: nil) { _, correlations, _ in
                let unit = HKUnit.millimeterOfMercury()
                var out: [BPReading] = []
                for c in correlations ?? [] {
                    guard let s = c.objects(for: sys).first as? HKQuantitySample,
                          let d = c.objects(for: dia).first as? HKQuantitySample else { continue }
                    out.append(BPReading(time: c.startDate, sys: s.quantity.doubleValue(for: unit), dia: d.quantity.doubleValue(for: unit)))
                }
                cont.resume(returning: out.sorted { $0.time < $1.time })
            }
            store.execute(q)
        }
    }
}
