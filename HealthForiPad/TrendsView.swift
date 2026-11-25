import SwiftUI
import Charts

/// Long-term view over everything in the cache: weight against activity, and year-over-year comparison.
/// Works on weekly / monthly averages, so many years stay readable and fast.
struct TrendsView: View {
    @Environment(DashboardStore.self) private var store
    @State private var bucket: Bucket = .month
    @State private var yoyField: Field = .weight
    @State private var selectedBin: Date?       // week / month start selected by touch-and-hold
    @State private var selectedMonth: Int?      // 1...12 on the year-vs-year chart

    enum Bucket: String, CaseIterable, Identifiable {
        case week = "Weekly", month = "Monthly"
        var id: String { rawValue }
        var component: Calendar.Component { self == .week ? .weekOfYear : .month }
    }

    private var yoyFields: [Field] { [Field.weight, .rhr, .activeKcal, .steps].filter { $0 == .weight || $0 == .rhr || hasHistory($0) } }

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

    private func yoyTitle(_ f: Field) -> String {
        switch f { case .rhr: return "RHR"; case .activeKcal: return "Active kcal"; default: return f.label }
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
                VStack(spacing: gap) {
                    longTermCard.frame(height: (h - gap) * 0.58)
                    yearCard.frame(height: (h - gap) * 0.42)
                }
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

    /// Metrics with enough history to be worth a panel (calories/steps only exist for the recent past in Garmin's API).
    private func hasHistory(_ f: Field) -> Bool { store.days.values.filter { $0[f] != nil }.count >= 60 }

    private struct Panel { let field: Field; let title: String; let color: Color; let bars: Bool; let decimals: Int }
    private var panels: [Panel] {
        var p = [Panel(field: .weight, title: "Weight kg", color: .primary, bars: false, decimals: 0),
                 Panel(field: .rhr, title: "Resting heart rate bpm", color: .red, bars: false, decimals: 0)]
        if hasHistory(.activeKcal) { p.append(Panel(field: .activeKcal, title: "Active kcal / day", color: .orange, bars: true, decimals: 0)) }
        return p
    }

    private var longTermCard: some View {
        let ps = panels
        let firstBin = ps.compactMap { bins($0.field).first?.date }.min()
        let dom: ClosedRange<Date>? = span.flatMap { s in firstBin.map { min($0, s.lowerBound).addingTimeInterval(-86400 * 3)...s.upperBound.addingTimeInterval(86400 * 20) } }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Long-term trends", systemImage: "chart.xyaxis.line").font(.headline)
                if let b = selectedBin {
                    Text(binLabel(b)).font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 3).background(Color.accentColor.opacity(0.18), in: Capsule())
                    Button("Clear") { withAnimation { selectedBin = nil } }.buttonStyle(.bordered).controlSize(.mini)
                }
                Spacer()
                Text(header).font(.caption).foregroundStyle(.secondary)
                Picker("", selection: $bucket) { ForEach(Bucket.allCases) { Text($0.rawValue).tag($0) } }
                    .pickerStyle(.segmented).frame(width: 170)
            }
            GeometryReader { g in
                VStack(spacing: 0) {
                    ForEach(Array(ps.enumerated()), id: \.offset) { i, p in
                        panel(p, dom, last: i == ps.count - 1).frame(height: g.size.height / Double(ps.count))
                    }
                }
            }
            Text("Average per \(bucket == .week ? "week" : "month") over all cached years, panels share one time axis.")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain).accessibilityLabel("Weight and resting heart rate over all years")
    }

    private func binLabel(_ d: Date) -> String {
        bucket == .month ? d.formatted(.dateTime.month(.wide).year()) : "Week of " + d.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private var allBinDates: [Date] { Array(Set(bins(.weight).map(\.date) + bins(.rhr).map(\.date))).sorted() }

    private func nearestBin(to d: Date) -> Date? { allBinDates.min { abs($0.timeIntervalSince(d)) < abs($1.timeIntervalSince(d)) } }

    private func yAxis() -> some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { v in
            AxisGridLine()
            AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: "%.0f", d)).monospacedDigit().frame(width: 40, alignment: .leading) } }
        }
    }

    private func panel(_ p: Panel, _ dom: ClosedRange<Date>?, last: Bool) -> some View {
        let b = bins(p.field)
        return Chart {
            if let sel = selectedBin {
                RuleMark(x: .value("Selected", sel)).foregroundStyle(.secondary.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                if let v = b.first(where: { $0.date == sel })?.value {
                    PointMark(x: .value("Date", sel), y: .value(p.title, v)).foregroundStyle(p.color).symbolSize(120)
                }
            }
            ForEach(b) { pt in
                if p.bars {
                    BarMark(x: .value("Date", pt.date, unit: bucket.component), y: .value(p.title, pt.value)).foregroundStyle(p.color.opacity(0.8))
                } else {
                    LineMark(x: .value("Date", pt.date), y: .value(p.title, pt.value)).foregroundStyle(p.color.opacity(0.9))
                        .interpolationMethod(.monotone).lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round))
                }
            }
        }
        .chartYScale(domain: .automatic(includesZero: p.bars))
        .modifier(OptionalXScale(domain: dom))
        .chartOverlay { proxy in
            TrendOverlay(proxy: proxy, onPick: { x in if let d = nearestBin(to: x) { selectedBin = d } }, onClear: { selectedBin = nil })
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 8)) { _ in
                AxisGridLine()
                if last { AxisTick(); AxisValueLabel(format: xFormat) }
            }
        }
        .chartYAxis { yAxis() }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 8) {
                Text(p.title).font(.caption2.weight(.bold))
                if let sel = selectedBin {
                    Text(b.first(where: { $0.date == sel }).map { p.field.format($0.value) } ?? "no data")
                        .font(.callout.monospacedDigit().weight(.semibold))
                }
            }
            .foregroundStyle(p.color == .primary ? .primary : p.color).padding(.leading, 6).padding(.top, 2)
        }
        .overlay { if b.isEmpty { Text("No data cached.").font(.callout).foregroundStyle(.secondary) } }
        .padding(.vertical, 7)       // keeps the end labels of neighbouring panels apart
    }

    private var xFormat: Date.FormatStyle {
        let days = span.map { Cal.cal.dateComponents([.day], from: $0.lowerBound, to: $0.upperBound).day ?? 0 } ?? 0
        return days > 900 ? .dateTime.year() : .dateTime.month(.abbreviated).year(.twoDigits)
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
                if let m = selectedMonth {
                    Text(Calendar.current.monthSymbols[m - 1]).font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 3).background(Color.accentColor.opacity(0.18), in: Capsule())
                    Button("Clear") { withAnimation { selectedMonth = nil } }.buttonStyle(.bordered).controlSize(.mini)
                }
                Spacer()
                Picker("", selection: $yoyField) { ForEach(yoyFields, id: \.self) { f in Text(yoyTitle(f)).tag(f) } }
                    .pickerStyle(.segmented).frame(maxWidth: 300)
            }
            Chart {
                if let m = selectedMonth {
                    RuleMark(x: .value("Month", m)).foregroundStyle(.secondary.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                }
                ForEach(lines) { l in
                    let c: Color = color(l.year)
                    let w: CGFloat = l.year == current ? 3.6 : 1.8
                    let yName: String = String(l.year)
                    ForEach(l.points, id: \.month) { pt in
                        LineMark(x: .value("Month", pt.month), y: .value("Value", pt.value), series: .value("Year", yName))
                            .foregroundStyle(c)
                            .interpolationMethod(.monotone)
                            .lineStyle(StrokeStyle(lineWidth: w, lineCap: .round))
                    }
                }
            }
            .chartXScale(domain: 1...12)
            .chartYScale(domain: .automatic(includesZero: false))
            .chartOverlay { proxy in
                TrendOverlay(proxy: proxy, onPick: { (x: Double) in selectedMonth = min(12, max(1, Int(x.rounded()))) }, onClear: { selectedMonth = nil })
            }
            .chartXAxis {
                AxisMarks(values: Array(1...12)) { v in
                    AxisGridLine()
                    AxisValueLabel { if let m = v.as(Int.self) { Text(Calendar.current.shortMonthSymbols[m - 1]).font(.caption2) } }
                }
            }
            .chartYAxis { yAxis() }
            .overlay { if lines.isEmpty { Text("No data cached for this metric.").font(.callout).foregroundStyle(.secondary) } }
            // legend: one chip per year
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(years.reversed(), id: \.self) { y in
                        HStack(spacing: 4) {
                            Capsule().fill(color(y)).frame(width: 14, height: y == current ? 4 : 3)
                            Text(String(y)).font(.caption).foregroundStyle(y == current ? .primary : .secondary)
                            if let m = selectedMonth {
                                let v = lines.first { $0.year == y }?.points.first { $0.month == m }?.value
                                Text(v.map { yoyField.format($0) } ?? "–").font(.caption.monospacedDigit().weight(.semibold))
                            }
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


/// Touch-and-hold, then drag, on a trend chart. Reports the x value under the finger (a Date or a Double); tap clears.
private struct TrendOverlay<X: Plottable>: View {
    let proxy: ChartProxy
    let onPick: (X) -> Void
    let onClear: () -> Void

    var body: some View {
        GeometryReader { geo in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { onClear() } }
                .gesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onChanged { value in
                            guard case .second(true, let drag) = value, let drag, let frame = proxy.plotFrame else { return }
                            let x = drag.location.x - geo[frame].origin.x
                            guard let v: X = proxy.value(atX: x) else { return }
                            withAnimation(.snappy(duration: 0.15)) { onPick(v) }
                        }
                )
        }
    }
}
