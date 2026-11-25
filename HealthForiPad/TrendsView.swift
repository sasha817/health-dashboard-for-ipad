import SwiftUI
import Charts

/// Long-term view over everything in the cache: weight against activity, and year-over-year comparison.
/// Works on weekly / monthly averages, so many years stay readable and fast.
struct TrendsView: View {
    @Environment(DashboardStore.self) private var store
    @State private var bucket: Bucket = .month
    @State private var yoyField: Field = .weight

    enum Bucket: String, CaseIterable, Identifiable {
        case week = "Weekly", month = "Monthly"
        var id: String { rawValue }
        var component: Calendar.Component { self == .week ? .weekOfYear : .month }
    }

    private let yoyFields: [Field] = [.weight, .rhr, .activeKcal, .steps]

    // MARK: aggregation

    private struct Bin: Identifiable { let date: Date; let value: Double; var id: Date { date } }

    /// Average of `f` per week / month over all cached days (days without the field are ignored).
    private func bins(_ f: Field) -> [Bin] {
        var sum: [Date: (Double, Int)] = [:]
        for p in store.days.values {
            guard let v = p[f], let start = Cal.cal.dateInterval(of: bucket.component, for: p.date)?.start else { continue }
            let s = sum[start] ?? (0, 0)
            sum[start] = (s.0 + v, s.1 + 1)
        }
        return sum.map { Bin(date: $0.key, value: $0.value.0 / Double($0.value.1)) }.sorted { $0.date < $1.date }
    }

    private var span: ClosedRange<Date>? {
        let all = store.days.values.filter { !$0.values.isEmpty }.map(\.date)
        guard let a = all.min(), let b = all.max() else { return nil }
        return a...b
    }

    private struct YearLine: Identifiable { let year: Int; let points: [(month: Int, value: Double)]; var id: Int { year } }

    private func yearLines(_ f: Field) -> [YearLine] {
        var sum: [Int: [Int: (Double, Int)]] = [:]
        for p in store.days.values {
            guard let v = p[f] else { continue }
            let c = Cal.cal.dateComponents([.year, .month], from: p.date)
            guard let y = c.year, let m = c.month else { continue }
            let s = sum[y]?[m] ?? (0, 0)
            sum[y, default: [:]][m] = (s.0 + v, s.1 + 1)
        }
        return sum.keys.sorted().map { y in
            YearLine(year: y, points: sum[y]!.keys.sorted().map { ($0, sum[y]![$0]!.0 / Double(sum[y]![$0]!.1)) })
        }
    }

    // MARK: view

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 12
            let h = geo.size.height - 28
            if geo.size.width > geo.size.height {
                HStack(spacing: gap) {
                    longTermCard.frame(width: (geo.size.width - 32 - gap) * 0.58)
                    yearCard.frame(maxWidth: .infinity)
                }
                .frame(height: h)
                .padding(.horizontal, 16).padding(.vertical, 14)
            } else {
                ScrollView {
                    VStack(spacing: gap) { longTermCard.frame(height: 520); yearCard.frame(height: 420) }
                        .padding(16).padding(.bottom, 56)
                }
            }
        }
    }

    private var header: String {
        guard let s = span else { return "No data cached yet" }
        let f = { (d: Date) in d.formatted(.dateTime.month(.abbreviated).year()) }
        return "\(f(s.lowerBound)) – \(f(s.upperBound)) · \(store.days.count) days"
    }

    private var weightBins: [Bin] { bins(.weight) }
    private var activityBins: [Bin] { bins(.activeKcal) }

    private var longTermCard: some View {
        let firstBin = ([weightBins.first?.date, activityBins.first?.date].compactMap { $0 }).min()
        let dom: ClosedRange<Date>? = span.flatMap { s in firstBin.map { min($0, s.lowerBound).addingTimeInterval(-86400 * 3)...s.upperBound.addingTimeInterval(86400 * 20) } }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Weight & activity", systemImage: "chart.xyaxis.line").font(.headline)
                Spacer()
                Text(header).font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $bucket) { ForEach(Bucket.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 170)
            }
            GeometryReader { g in
                VStack(spacing: 0) {
                    chartWeight(dom).frame(height: g.size.height * 0.6)
                    chartActivity(dom).frame(height: g.size.height * 0.4)
                }
            }
            Text("Average per \(bucket == .week ? "week" : "month"). Bars: average active calories burned per day (Garmin has no calories eaten).")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain).accessibilityLabel("Weight and activity over all years")
    }

    private func yAxis(_ unit: String) -> some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
            AxisGridLine()
            AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: "%.0f", d)).monospacedDigit().frame(width: 40, alignment: .leading) } }
        }
    }

    private func chartWeight(_ dom: ClosedRange<Date>?) -> some View {
        let b = weightBins
        return Chart {
            ForEach(b) { p in
                LineMark(x: .value("Date", p.date), y: .value("Weight", p.value)).foregroundStyle(Color.primary.opacity(0.85))
                    .interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .modifier(OptionalXScale(domain: dom))
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 12)) { _ in AxisGridLine() } }
        .chartYAxis { yAxis("kg") }
        .overlay(alignment: .topLeading) { Text("Weight kg").font(.caption2.weight(.bold)).padding(.leading, 6).padding(.top, 2) }
        .overlay { if b.isEmpty { Text("No weight data cached.").font(.callout).foregroundStyle(.secondary) } }
        .padding(.bottom, 6)
    }

    private func chartActivity(_ dom: ClosedRange<Date>?) -> some View {
        let b = activityBins
        return Chart {
            ForEach(b) { p in
                BarMark(x: .value("Date", p.date, unit: bucket.component), y: .value("Active kcal", p.value))
                    .foregroundStyle(Color.orange.opacity(0.8))
            }
        }
        .modifier(OptionalXScale(domain: dom))
        .chartXAxis { AxisMarks(values: .automatic(desiredCount: 7)) { _ in AxisGridLine(); AxisTick(); AxisValueLabel(format: .dateTime.year()) } }
        .chartYAxis { yAxis("kcal") }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Text("Active kcal / day").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                if b.isEmpty { Text("not downloaded yet — refresh").font(.caption2).foregroundStyle(.secondary) }
            }.padding(.leading, 6).padding(.top, 2)
        }
        .padding(.top, 6)
    }

    // MARK: year vs year

    private var yearCard: some View {
        let lines = yearLines(yoyField)
        let years = lines.map { $0.year }
        let current = Cal.cal.component(.year, from: Date())
        func color(_ y: Int) -> Color {
            if y == current { return .accentColor }
            let idx = Double(years.firstIndex(of: y) ?? 0) / Double(max(1, years.count - 1))
            return Color(hue: 0.08 + 0.55 * idx, saturation: 0.55, brightness: 0.8).opacity(0.75)
        }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Year vs. year", systemImage: "calendar").font(.headline).lineLimit(1).fixedSize()
                Spacer()
                Picker("", selection: $yoyField) { ForEach(yoyFields, id: \.self) { Text($0 == .rhr ? "RHR" : $0 == .activeKcal ? "Active kcal" : $0.label).tag($0) } }
                    .pickerStyle(.segmented).frame(maxWidth: 300)
            }
            Chart {
                ForEach(lines) { l in
                    ForEach(l.points, id: \.month) { pt in
                        LineMark(x: .value("Month", pt.month), y: .value(yoyField.label, pt.value), series: .value("Year", String(l.year)))
                            .foregroundStyle(color(l.year))
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: l.year == current ? 3.6 : 1.8, lineCap: .round))
                    }
                }
            }
            .chartXScale(domain: 1...12)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis {
                AxisMarks(values: Array(1...12)) { v in
                    AxisGridLine()
                    AxisValueLabel { if let m = v.as(Int.self) { Text(Calendar.current.shortMonthSymbols[m - 1]).font(.caption2) } }
                }
            }
            .chartYAxis { yAxis("") }
            .overlay { if lines.isEmpty { Text("No data cached for this metric.").font(.callout).foregroundStyle(.secondary) } }
            // legend: one chip per year
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(years.reversed(), id: \.self) { y in
                        HStack(spacing: 4) {
                            Capsule().fill(color(y)).frame(width: 14, height: y == current ? 4 : 3)
                            Text(String(y)).font(.caption).foregroundStyle(y == current ? .primary : .secondary)
                        }
                    }
                }
            }
            Text("Monthly average of each year on the same January–December axis; the current year is the thick line.")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain).accessibilityLabel("Year versus year comparison of \(yoyField.label)")
    }
}

private struct OptionalXScale: ViewModifier {
    let domain: ClosedRange<Date>?
    func body(content: Content) -> some View {
        if let d = domain { content.chartXScale(domain: d) } else { content }
    }
}
