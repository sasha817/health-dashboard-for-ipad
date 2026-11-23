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

    /// Daily average systolic/diastolic, keyed by noon-of-day.
    static func fetch(from: Date, to: Date) async -> [Date: [Field: Double]] {
        async let s = daily(sys, .systolic, from, to)
        async let d = daily(dia, .diastolic, from, to)
        var out: [Date: [Field: Double]] = [:]
        for (date, v) in await s { out[date, default: [:]][.systolic] = v }
        for (date, v) in await d { out[date, default: [:]][.diastolic] = v }
        return out
    }

    private static func daily(_ type: HKQuantityType, _ field: Field, _ from: Date, _ to: Date) async -> [Date: Double] {
        let start = Cal.cal.startOfDay(for: from)
        let end = Cal.add(1, to: Cal.cal.startOfDay(for: to))
        let pred = HKQuery.predicateForSamples(withStart: start, end: end)
        return await withCheckedContinuation { cont in
            let q = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: pred,
                                                options: .discreteAverage, anchorDate: start,
                                                intervalComponents: DateComponents(day: 1))
            q.initialResultsHandler = { _, results, _ in
                var out: [Date: Double] = [:]
                results?.enumerateStatistics(from: start, to: end) { stat, _ in
                    if let v = stat.averageQuantity()?.doubleValue(for: .millimeterOfMercury()) {
                        out[Cal.noon(stat.startDate)] = v
                    }
                }
                cont.resume(returning: out)
            }
            store.execute(q)
        }
    }
}
