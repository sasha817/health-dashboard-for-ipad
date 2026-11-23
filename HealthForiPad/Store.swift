import Foundation
import Observation

@MainActor @Observable
final class DashboardStore {
    static let shared = DashboardStore()

    // MARK: state
    var range: TimeRange = .week
    var days: [Date: DayPoint] = [:]
    var selected: Date?
    var isLoading = false
    var errorMessage: String?
    var warnings: [String] = []
    var rawSamples: [String: String] = [:]
    var backfillProgress: Double?          // non-nil while a history download runs
    var backfillMessage: String?
    var cacheSummary = "Nothing cached yet"

    // MARK: settings (persisted in UserDefaults)
    var useDemo: Bool = UserDefaults.standard.bool(forKey: "useDemo") {
        didSet { UserDefaults.standard.set(useDemo, forKey: "useDemo") }
    }
    var bpGuideline: BPGuideline = BPGuideline(rawValue: UserDefaults.standard.string(forKey: "bpGuideline") ?? "") ?? .aha {
        didSet { UserDefaults.standard.set(bpGuideline.rawValue, forKey: "bpGuideline") }
    }
    /// Sleep goal in hours.
    var sleepGoal: Double = (UserDefaults.standard.object(forKey: "sleepGoal") as? Double) ?? 7.5 {
        didSet { UserDefaults.standard.set(sleepGoal, forKey: "sleepGoal") }
    }
    /// Rolling-average window in days; 0 = automatic (depends on the selected range).
    var rollingWindow: Int = (UserDefaults.standard.object(forKey: "rollingWindow") as? Int) ?? 14 {
        didSet { UserDefaults.standard.set(rollingWindow, forKey: "rollingWindow") }
    }
    var useHealthKit: Bool = UserDefaults.standard.bool(forKey: "useHealthKit") {
        didSet { UserDefaults.standard.set(useHealthKit, forKey: "useHealthKit") }
    }
    /// How far back history is kept / downloaded, in years.
    var historyYears: Int = (UserDefaults.standard.object(forKey: "historyYears") as? Int) ?? 1 {
        didSet {
            UserDefaults.standard.set(historyYears, forKey: "historyYears")
            if range == .twoYears && historyYears < 2 { range = .year }
        }
    }
    var autoBackfill: Bool = UserDefaults.standard.bool(forKey: "autoBackfill") {
        didSet { UserDefaults.standard.set(autoBackfill, forKey: "autoBackfill"); BackgroundSync.schedule() }
    }
    var autoRefresh: Bool = UserDefaults.standard.bool(forKey: "autoRefresh") {
        didSet { UserDefaults.standard.set(autoRefresh, forKey: "autoRefresh"); BackgroundSync.schedule() }
    }

    var availableRanges: [TimeRange] { TimeRange.allCases.filter { $0 != .twoYears || historyYears >= 2 } }

    var effectiveRollingDays: Int {
        if rollingWindow > 0 { return rollingWindow }
        switch range {
        case .week, .month: return 7
        case .quarter: return 14
        case .half, .year, .twoYears: return 28
        }
    }

    // MARK: private
    private var coveredStart: Date?
    private var coveredEnd: Date?
    private var lastRefresh: Date?
    private var cacheLoaded = false
    private var client: GarminClient?
    private var clientKey: String?
    private var backfillTask: Task<Void, Never>?
    private var rateLimitStreak = 0
    /// Persisted so a relaunch (or a background task) doesn't hammer Garmin while the quota is exhausted.
    private var rateLimitedUntil: Date? {
        get { UserDefaults.standard.object(forKey: "rateLimitedUntil") as? Date }
        set { UserDefaults.standard.set(newValue, forKey: "rateLimitedUntil") }
    }
    struct FetchOutcome { var rateLimited = false; var retryAfter: TimeInterval?; var requests = 0 }
    var isBackfilling: Bool { backfillTask != nil }

    var hasKey: Bool { Keychain.read() != nil }
    var needsSetup: Bool { !useDemo && !hasKey }

    /// Range start/end (noon-aligned).
    var window: (start: Date, end: Date) {
        let end = Cal.noon(Date())
        return (Cal.add(-(range.days - 1), to: end), end)
    }

    var visible: [DayPoint] {
        let w = window
        let n = effectiveRollingDays
        let inRange = days.values.filter { $0.date >= w.start && $0.date <= w.end }.sorted { $0.date < $1.date }
        let trends = bodyTrends(window: n)
        return inRange.map { p in
            var p = p
            // trailing rolling average of resting HR (needs ≥3 readings)
            let vals = (0..<n).compactMap { days[Cal.add(-$0, to: p.date)]?[.rhr] }
            if vals.count >= 3 { p.values[.rhrAvg] = vals.reduce(0, +) / Double(vals.count) }
            // smoothed body trends (only on days with a measurement)
            if let t = trends.weight[p.date] { p.values[.weightTrend] = t }
            if let t = trends.fat[p.date] { p.values[.fatMassTrend] = t }
            if let t = trends.lean[p.date] { p.values[.leanMassTrend] = t }
            if let t = trends.muscle[p.date] { p.values[.muscleTrend] = t }
            return p
        }
    }

    /// Exponentially weighted trends ("trend weight"): smooths daily water/scale noise much better than a plain average.
    /// Time-aware, so measurements every 2–3 days are handled correctly. Smoothing follows the trend-window setting.
    private func bodyTrends(window n: Int) -> (weight: [Date: Double], fat: [Date: Double], lean: [Date: Double], muscle: [Date: Double]) {
        let alpha = 2.0 / (Double(n) + 1)
        let all = days.values.sorted { $0.date < $1.date }
        func ewma(_ pts: [(Date, Double)]) -> [Date: Double] {
            var out: [Date: Double] = [:]
            var prev: Date?
            var t = 0.0
            for (d, v) in pts {
                if let pd = prev {
                    let gap = max(1, Cal.cal.dateComponents([.day], from: pd, to: d).day ?? 1)
                    t += (1 - pow(1 - alpha, Double(gap))) * (v - t)
                } else { t = v }
                out[d] = t; prev = d
            }
            return out
        }
        var fatPts: [(Date, Double)] = [], leanPts: [(Date, Double)] = []
        for p in all {
            if let w = p[.weight], let bf = p[.bodyFat] { let fat = w * bf / 100; fatPts.append((p.date, fat)); leanPts.append((p.date, w - fat)) }
        }
        return (ewma(all.compactMap { p in p[.weight].map { (p.date, $0) } }), ewma(fatPts), ewma(leanPts),
                ewma(all.compactMap { p in p[.muscleMass].map { (p.date, $0) } }))
    }

    func setRange(_ r: TimeRange) {
        range = r
        if let s = selected, s < window.start { selected = nil }
        Task { await load() }
    }

    // MARK: Apple Health (blood pressure)
    func enableHealthKit() async -> String? {
        guard HealthKitBP.available else { return "Apple Health is not available on this device." }
        do { try await HealthKitBP.requestAccess(); useHealthKit = true; await mergeHealthKit(); return nil }
        catch { return error.localizedDescription }
    }

    func disableHealthKit() {
        useHealthKit = false
        for (d, var p) in days { p.values[.systolic] = nil; p.values[.diastolic] = nil; days[d] = p }
    }

    func mergeHealthKit() async {
        guard useHealthKit, HealthKitBP.available else { return }
        let w = window
        let series = await HealthKitBP.fetch(from: w.start, to: w.end)
        for (date, vals) in series {
            var p = days[date] ?? DayPoint(date: date)
            for (f, v) in vals { p.values[f] = v }
            days[date] = p
        }
    }

    // MARK: cache
    private func loadCacheIfNeeded() {
        guard !cacheLoaded else { return }
        cacheLoaded = true
        guard let c = DiskCache.load() else { return }
        for d in c.days {
            var p = DayPoint(date: d.date)
            for (k, v) in d.values { if let f = Field(rawValue: k) { p.values[f] = v } }
            days[d.date] = p
        }
        // caches from before sleep stages / body composition existed keep their days but are re-fetched (coverage dropped)
        if c.version >= 5 { coveredStart = c.coveredStart; coveredEnd = c.coveredEnd; lastRefresh = c.lastRefresh }
        updateSummary()
    }

    private func saveCache() {
        let list = days.values.compactMap { p -> CachedDay? in
            let v = Dictionary(uniqueKeysWithValues: DiskCache.persisted.compactMap { f in p[f].map { (f.rawValue, $0) } })
            return v.isEmpty ? nil : CachedDay(date: p.date, values: v)
        }
        DiskCache.save(CacheFile(coveredStart: coveredStart, coveredEnd: coveredEnd, lastRefresh: lastRefresh, days: list))
        updateSummary()
    }

    private func updateSummary() {
        guard let cs = coveredStart, let ce = coveredEnd else { cacheSummary = "Nothing cached yet"; return }
        let f = { (d: Date) in d.formatted(date: .abbreviated, time: .omitted) }
        cacheSummary = "\(days.count) days · \(f(cs)) – \(f(ce))"
    }

    /// Wipes the cache (memory + disk).
    func clearCache() {
        backfillTask?.cancel()
        days = [:]; coveredStart = nil; coveredEnd = nil; lastRefresh = nil; selected = nil
        warnings = []; rawSamples = [:]; errorMessage = nil; backfillMessage = nil
        DiskCache.delete(); cacheLoaded = true
        updateSummary()
    }

    /// The API key was replaced (e.g. renewed): keep the cache, rebuild the client.
    func keyChanged() { client = nil; clientKey = nil; errorMessage = nil }

    /// Demo mode toggled: drop what's in memory; the cache is re-read from disk on the next load.
    func switchedDemo() { days = [:]; selected = nil; cacheLoaded = false; coveredStart = nil; coveredEnd = nil; lastRefresh = nil; errorMessage = nil; updateSummary() }

    // MARK: loading
    /// Loads what the current range needs. Cached days are shown instantly; only missing or stale days are fetched.
    /// `manual` (pull-to-refresh / refresh button) re-fetches the last two weeks regardless of cache freshness.
    func load(manual: Bool = false) async {
        guard !isLoading else { return }
        errorMessage = nil
        if useDemo {
            days = Demo.generate(); coveredStart = nil
            await mergeHealthKit()
            return
        }
        loadCacheIfNeeded()
        guard ensureClient() != nil else {
            await mergeHealthKit()
            errorMessage = "No API key set. Open Settings to add one."; return
        }
        isLoading = true
        defer { isLoading = false }

        let today = Cal.noon(Date())
        let needFrom = Cal.add(-27, to: window.start)   // extra history for the longest (28-day) rolling window
        var ws: [(Date, Date)] = []
        if let cs = coveredStart, let ce = coveredEnd {
            if needFrom < cs { ws.append((needFrom, Cal.add(-1, to: cs))) }
            let fresh = !manual && ce >= today && (lastRefresh.map { Date().timeIntervalSince($0) < 600 } ?? false)
            if !fresh {
                var s = Cal.add(-6, to: ce)
                if manual { s = min(s, Cal.add(-13, to: today)) }
                ws.append((max(cs, s), today))
            }
        } else {
            ws = [(needFrom, today)]
        }
        if !ws.isEmpty, let until = rateLimitedUntil, until > Date() {
            warnings = ["Garmin rate limit active until \(until.formatted(date: .omitted, time: .shortened)); showing cached data."]
            ws = []
        }
        if !ws.isEmpty {
            let touchesNewest = ws.contains { $0.1 >= today }
            await runFetch(ws)
            if touchesNewest { lastRefresh = Date() }
            saveCache()
        }
        await mergeHealthKit()
        if autoBackfill && !isBackfilling { startBackfill() }
    }

    /// Background-friendly: refresh only the newest days.
    func syncLatest() async {
        guard !useDemo else { return }
        loadCacheIfNeeded()
        guard ensureClient() != nil else { return }
        if let until = rateLimitedUntil, until > Date() { return }
        let today = Cal.noon(Date())
        let from = coveredEnd.map { max(coveredStart ?? $0, Cal.add(-6, to: $0)) } ?? Cal.add(-83, to: today)
        await runFetch([(from, today)])
        lastRefresh = Date()
        saveCache()
    }

    // MARK: history download
    func startBackfill() {
        guard backfillTask == nil, !useDemo else { return }
        backfillTask = Task { [weak self] in
            await self?.backfill()
            self?.backfillTask = nil
        }
    }

    func cancelBackfill() { backfillTask?.cancel() }

    /// Downloads history backwards in 12-week steps until `historyYears` is reached. Resumable: every step is saved.
    /// Works in batches: after ~80 requests it pauses, and when Garmin reports a rate limit it waits (escalating) and continues.
    /// In `background` mode it never waits; it saves and returns.
    func backfill(background: Bool = false) async {
        loadCacheIfNeeded()
        guard ensureClient() != nil else { backfillMessage = "No API key set."; return }
        let today = Cal.noon(Date())
        let target = Cal.add(-(historyYears * 365), to: today)
        let batchBudget = 80
        var used = 0
        backfillMessage = nil

        func wait(_ seconds: Int, _ reason: String) async -> Bool {
            var r = seconds
            while r > 0 {
                if Task.isCancelled { return false }
                backfillMessage = "\(reason) Resuming in \(r / 60):\(String(format: "%02d", r % 60))…"
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                r -= 1
            }
            backfillMessage = nil
            return !Task.isCancelled
        }

        if coveredStart == nil || coveredEnd == nil {
            let o = await runFetch([(Cal.add(-83, to: today), today)]); used += o.requests; saveCache()
            if o.rateLimited && background { backfillProgress = nil; return }
        }
        let span = Double(max(1, Cal.cal.dateComponents([.day], from: target, to: today).day ?? 1))
        var stalls = 0
        while !Task.isCancelled, let cs = coveredStart, cs > target {
            backfillProgress = min(1, max(0, Double(Cal.cal.dateComponents([.day], from: cs, to: today).day ?? 0) / span))
            if let until = rateLimitedUntil, until > Date() {
                if background { backfillProgress = nil; return }
                if !(await wait(Int(until.timeIntervalSinceNow) + 1, "Garmin rate limit.")) { break }
            }
            if used + 9 > batchBudget {      // batch finished: breathe before the next one
                if background { backfillProgress = nil; return }
                if !(await wait(75, "Batch done (\(used) requests), pausing to respect Garmin's limit.")) { break }
                used = 0
            }
            let from = max(target, Cal.add(-84, to: cs))
            let o = await runFetch([(from, Cal.add(-1, to: cs))])
            used += o.requests
            saveCache()
            if o.rateLimited {
                if background { backfillProgress = nil; return }
                used = 0
                continue                      // the wait happens at the top of the loop (rateLimitedUntil is set)
            }
            if coveredStart == cs {           // no progress without a rate limit: genuine error
                stalls += 1
                if stalls >= 2 {
                    backfillMessage = Task.isCancelled ? "Stopped. Progress is saved; continue any time."
                                                       : "Paused after an error. Progress is saved; try again later."
                    backfillProgress = nil
                    return
                }
            } else { stalls = 0 }
            try? await Task.sleep(nanoseconds: 600_000_000)
        }
        backfillProgress = nil
        if let cs = coveredStart, cs <= target { backfillMessage = "History is complete back to \(target.formatted(date: .abbreviated, time: .omitted))." }
        else if Task.isCancelled { backfillMessage = "Stopped. Progress is saved; continue any time." }
    }

    // MARK: network
    private func ensureClient() -> GarminClient? {
        guard let key = Keychain.read() else { return nil }
        if client == nil || clientKey != key { client = GarminClient(apiKey: key); clientKey = key }
        return client
    }

    private static func isTransient(_ error: Error) -> Bool {
        if case GarminError.http(let code, _) = error { return code == 401 || code == 408 || code == 429 || code >= 500 }
        return true   // network errors, cancellation, …
    }

    /// Fetches the given windows (split into ≤28-day chunks), merges results into `days` and extends the coverage by every chunk that completed without a transient error.
    @discardableResult
    private func runFetch(_ windows: [(Date, Date)]) async -> FetchOutcome {
        var outcome = FetchOutcome()
        guard let client else { return outcome }
        var chunks: [(Date, Date)] = []
        for (a, b) in windows where a <= b {
            var s = a
            while s <= b {
                let e = min(Cal.add(27, to: s), b)
                chunks.append((s, e)); s = Cal.add(1, to: e)
            }
        }
        let jobs = Parsing.jobs()
        var tasks: [(Int, Job)] = []
        for i in chunks.indices { for j in jobs { tasks.append((i, j)) } }

        var remaining = Dictionary(uniqueKeysWithValues: chunks.indices.map { ($0, jobs.count) })
        var bad = Set<Int>()
        var failures: [String: String] = [:]
        var okJobs = Set<String>()
        var abort = false
        var index = 0
        while index < tasks.count && !abort && !Task.isCancelled {
            let batch = Array(tasks[index..<min(index + 5, tasks.count)]); index += 5
            outcome.requests += batch.count
            await withTaskGroup(of: (Int, String, [Date: [Field: Double]]?, String, Error?).self) { group in
                for (ci, job) in batch {
                    let (a, b) = chunks[ci]
                    group.addTask {
                        do {
                            let data = try await client.get(job.path(a, b), query: Parsing.query(for: job, from: a, to: b))
                            let parsed = Parsing.parse(data, job: job)
                            let pretty = (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed))
                                .flatMap { try? JSONSerialization.data(withJSONObject: $0, options: [.prettyPrinted, .sortedKeys]) }
                                .flatMap { String(data: $0, encoding: .utf8) } ?? String(data: data, encoding: .utf8) ?? ""
                            return (ci, job.name, parsed, String(pretty.prefix(8000)), nil)
                        } catch {
                            return (ci, job.name, nil, "", error)
                        }
                    }
                }
                for await (ci, name, parsed, raw, err) in group {
                    remaining[ci, default: 0] -= 1
                    if let err {
                        failures[name] = err.localizedDescription
                        rawSamples[name] = "ERROR: " + err.localizedDescription
                        if Self.isTransient(err) { bad.insert(ci) }
                        if case GarminError.rateLimited(let ra, let body) = err {
                            abort = true; outcome.rateLimited = true; outcome.retryAfter = ra
                            rawSamples["Rate limit"] = String(body.prefix(2000))
                        }
                        continue
                    }
                    okJobs.insert(name)
                    if rawSamples[name] == nil || rawSamples[name]!.hasPrefix("ERROR") { rawSamples[name] = raw }
                    for (date, vals) in parsed ?? [:] {
                        var p = days[date] ?? DayPoint(date: date)
                        for (f, v) in vals { p.values[f] = v }
                        days[date] = p
                    }
                }
            }
        }
        if outcome.rateLimited {
            // escalating cool-down: 75 s, 5 min, 20 min, then ~65 min (Garmin does not document the window)
            let steps: [TimeInterval] = [75, 300, 1200, 3900]
            let wait = outcome.retryAfter ?? steps[min(rateLimitStreak, steps.count - 1)]
            rateLimitStreak += 1
            rateLimitedUntil = Date().addingTimeInterval(wait)
        } else if okJobs.count > 0 { rateLimitStreak = 0; rateLimitedUntil = nil }
        warnings = failures.map { "\($0.key): \($0.value)" }.sorted()
        if okJobs.isEmpty, let first = failures.values.first { errorMessage = first }

        // coverage = the contiguous run of completed chunks that reaches closest to today
        var done = chunks.indices.filter { remaining[$0] == 0 && !bad.contains($0) }.map { chunks[$0] }
        if let cs = coveredStart, let ce = coveredEnd { done.append((cs, ce)) }
        done.sort { $0.0 < $1.0 }
        var merged: [(Date, Date)] = []
        for iv in done {
            if var last = merged.last, iv.0 <= Cal.add(1, to: last.1) { last.1 = max(last.1, iv.1); merged[merged.count - 1] = last }
            else { merged.append(iv) }
        }
        if let best = merged.max(by: { $0.1 < $1.1 }) { coveredStart = best.0; coveredEnd = best.1 }
        return outcome
    }
}
