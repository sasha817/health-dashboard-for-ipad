import XCTest
@testable import HealthForiPad

/// Regression tests for the Garmin response parser and the calendar-day handling.
final class ParsingTests: XCTestCase {
    private func job(_ name: String) -> Job { Parsing.jobs().first { $0.name == name }! }

    /// Parse a JSON document with the named job; results keyed by "yyyy-MM-dd".
    private func parse(_ json: String, _ jobName: String) -> [String: [Field: Double]] {
        let r = Parsing.parse(Data(json.utf8), job: job(jobName))
        return Dictionary(uniqueKeysWithValues: r.map { (Cal.iso($0.key), $0.value) })
    }

    func testCaloriesStepsAndIntensityMinutes() {
        let json = #"[{"calendarDate":"2026-11-17","calories":{"burnedActive":238,"burnedResting":2142,"burnedTotal":2380},"movement":{"steps":{"distanceInMeters":6054,"goal":7000,"value":7247}},"intensityMinutes":{"goal":150,"moderate":5,"vigorous":0}}]"#
        let r = parse(json, "Daily summaries")["2026-11-17"]
        XCTAssertEqual(r?[.activeKcal], 238)
        XCTAssertEqual(r?[.restingKcal], 2142)
        XCTAssertEqual(r?[.steps], 7247)
        XCTAssertEqual(r?[.moderateMin], 5)
        XCTAssertEqual(r?[.vigorousMin], 0)
    }

    func testWrapperWithDateKeyDoesNotSwallowItsDays() {
        let json = #"{"date":"2026-05-01","data":[{"calendarDate":"2026-05-01","heartRate":{"restingValue":55}},{"calendarDate":"2026-05-02","heartRate":{"restingValue":57}}]}"#
        let r = parse(json, "Daily summaries")
        XCTAssertEqual(r["2026-05-01"]?[.rhr], 55)
        XCTAssertEqual(r["2026-05-02"]?[.rhr], 57)
    }

    func testZeroIsAValidValueWhereZeroIsReal() {
        let json = #"[{"calendarDate":"2026-05-01","awakeCount":0,"deepSleepSeconds":0,"lightSleepSeconds":18000,"remSleepSeconds":3600,"awakeSleepSeconds":0,"sleepTimeSeconds":21600}]"#
        let r = parse(json, "Sleep")["2026-05-01"]
        XCTAssertEqual(r?[.awakeCount], 0)
        XCTAssertEqual(r?[.sleepDeep], 0)
        XCTAssertEqual(r?[.sleepAwake], 0)
        XCTAssertEqual(r?[.sleepHours] ?? -1, 6, accuracy: 1e-9)
    }

    func testNegativeAndZeroStressMeanNoData() {
        let json = #"[{"calendarDate":"2026-05-01","stress":{"avgLevel":-1}},{"calendarDate":"2026-05-02","stress":{"avgLevel":31}}]"#
        let r = parse(json, "Daily summaries")
        XCTAssertNil(r["2026-05-01"]?[.stress])
        XCTAssertEqual(r["2026-05-02"]?[.stress], 31)
    }

    func testShallowestOccurrenceOfAKeyWins() {
        let json = #"[{"calendarDate":"2026-05-01","avgHeartRate":52,"sleepMovement":{"avgHeartRate":90}}]"#
        XCTAssertEqual(parse(json, "Sleep")["2026-05-01"]?[.sleepHR], 52)
    }

    func testTheSameMeasurementListedTwiceCountsOnce() {
        // "latest" repeats one of the entries of "all": the mean must be (80 + 81) / 2, not weighted towards 81
        let json = #"""
        {"dailyWeightSummaries":[{"summaryDate":"2026-05-01",
           "latestWeight":{"calendarDate":"2026-05-01","weight":81000},
           "allWeightMetrics":[{"calendarDate":"2026-05-01","weight":80000},{"calendarDate":"2026-05-01","weight":81000}]}]}
        """#
        XCTAssertEqual(parse(json, "Weight")["2026-05-01"]?[.weight] ?? 0, 80.5, accuracy: 1e-9)
    }

    func testWeightInGramsIsConvertedToKg() {
        let json = #"[{"calendarDate":"2026-05-01","weight":79400.0,"bodyFat":18.5,"muscleMass":33100}]"#
        let r = parse(json, "Weight")["2026-05-01"]
        XCTAssertEqual(r?[.weight] ?? 0, 79.4, accuracy: 1e-9)
        XCTAssertEqual(r?[.bodyFat] ?? 0, 18.5, accuracy: 1e-9)
        XCTAssertEqual(r?[.muscleMass] ?? 0, 33.1, accuracy: 1e-9)
    }

    func testNestedSleepScoreAndIdealRanges() {
        let json = #"[{"calendarDate":"2026-05-01","sleepScores":{"overall":{"value":82},"deepPercentage":{"value":19,"idealStartInSeconds":4252.8,"idealEndInSeconds":8771.4}}}]"#
        let r = parse(json, "Sleep")["2026-05-01"]
        XCTAssertEqual(r?[.sleepScore], 82)
        XCTAssertEqual(r?[.deepLo] ?? 0, 4252.8 / 3600, accuracy: 1e-9)
    }

    func testPayloadValidation() {
        XCTAssertTrue(Parsing.isValidPayload(Data("[]".utf8)))
        XCTAssertTrue(Parsing.isValidPayload(Data("{}".utf8)))
        XCTAssertTrue(Parsing.isValidPayload(Data("null".utf8)))          // what a 204 is turned into
        XCTAssertFalse(Parsing.isValidPayload(Data()))
        XCTAssertFalse(Parsing.isValidPayload(Data("<html>Service unavailable</html>".utf8)))
    }

    func testCalendarDayRoundTripIsStable() {
        for day in ["2026-03-29", "2026-10-25", "2026-12-31"] {      // includes the EU DST change days
            let d = Cal.parse(day)!
            XCTAssertEqual(Cal.iso(d), day)
            XCTAssertEqual(Cal.cal.component(.hour, from: d), 12)
        }
    }

    func testCachedDayPrefersTheCalendarDateString() {
        let legacyAbsolute = Date(timeIntervalSince1970: 0)
        let c = CachedDay(day: "2026-05-01", date: legacyAbsolute, values: [:])
        XCTAssertEqual(c.resolvedDate.map(Cal.iso), "2026-05-01")
        XCTAssertNotNil(CachedDay(day: nil, date: legacyAbsolute, values: [:]).resolvedDate)   // old caches still load
    }

    // MARK: blood-pressure categories (worse of systolic / diastolic)

    func testAHACategories() {
        let g = BPGuideline.aha
        XCTAssertEqual(g.category(sys: 119, dia: 79), 0)
        XCTAssertEqual(g.category(sys: 125, dia: 70), 1)     // elevated: systolic 120–129 only
        XCTAssertEqual(g.category(sys: 118, dia: 85), 2)     // diastolic 80–89 is stage 1 (AHA has no "elevated" for diastolic)
        XCTAssertEqual(g.category(sys: 110, dia: 92), 3)
        XCTAssertEqual(g.category(sys: 150, dia: 70), 3)
        XCTAssertEqual(g.diaCategory(102), 3)                // the case a shared axis got wrong (it looked green)
    }

    func testESCCategories() {
        let g = BPGuideline.esc
        XCTAssertEqual(g.category(sys: 125, dia: 80), 0)
        XCTAssertEqual(g.category(sys: 135, dia: 70), 1)
        XCTAssertEqual(g.category(sys: 150, dia: 95), 2)
        XCTAssertEqual(g.category(sys: 165, dia: 60), 3)
        XCTAssertEqual(g.diaCategory(87), 1)
    }

    func testZoneBandsCoverTheAxisWithoutGaps() {
        for g in BPGuideline.allCases {
            for zones in [g.sysZones, g.diaZones] {
                XCTAssertEqual(zones.first?.from, 0)
                for (a, b) in zip(zones, zones.dropFirst()) { XCTAssertEqual(a.to, b.from) }
                XCTAssertGreaterThanOrEqual(zones.last?.to ?? 0, 400)
            }
        }
    }
}
