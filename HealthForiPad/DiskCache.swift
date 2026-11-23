import Foundation

struct CachedDay: Codable {
    var date: Date
    var values: [String: Double]
}

struct CacheFile: Codable {
    var version = 5
    var coveredStart: Date?
    var coveredEnd: Date?
    var lastRefresh: Date?
    var days: [CachedDay] = []
}

/// Garmin data cache on disk (Application Support, excluded from iCloud backup).
/// Apple Health values (blood pressure) are never cached; they are re-read from Health each time.
enum DiskCache {
    private static var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("garmin-cache.json")
    }

    static let persisted: [Field] = [.rhr, .sleepStart, .sleepEnd, .awakeCount, .deepLo, .deepHi, .lightLo, .lightHi, .remLo, .remHi, .sleepHours, .sleepScore, .sleepDeep, .sleepLight, .sleepRem, .sleepAwake, .spo2Avg, .spo2Low, .respAvg, .sleepHR, .sleepStress, .weight, .bodyFat, .muscleMass, .stress]

    static func load() -> CacheFile? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CacheFile.self, from: data)
    }

    static func save(_ file: CacheFile) {
        guard let data = try? JSONEncoder().encode(file) else { return }
        var u = url
        try? data.write(to: u, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        var rv = URLResourceValues(); rv.isExcludedFromBackup = true
        try? u.setResourceValues(rv)
    }

    static func delete() { try? FileManager.default.removeItem(at: url) }
}
