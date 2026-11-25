import SwiftUI
import Charts

/// Weight split into lean and fat mass (stacked area, smoothed) with the weight trend on top,
/// and a muscle-mass trend panel underneath. Both panels share the x axis and the day selection.
struct BodyCompositionCard: View {
    let days: [DayPoint]
    let range: TimeRange
    let window: (start: Date, end: Date)
    @Binding var selected: Date?
    let trendDays: Int

    private var selectedPoint: DayPoint? { selected.flatMap { s in days.first { $0.date == s } } }
    private let leanColor = Color.teal, fatColor = Color.orange, muscleColor = Color.purple

    // MARK: derived data

    /// Days with lean/fat trend, split into segments at gaps longer than 10 days (so the area doesn't bridge long pauses).
    private var segments: [[DayPoint]] {
        var out: [[DayPoint]] = [], cur: [DayPoint] = []
        for d in days where d[.leanMassTrend] != nil && d[.fatMassTrend] != nil {
            if let last = cur.last, Cal.cal.dateComponents([.day], from: last.date, to: d.date).day ?? 0 > 10 { out.append(cur); cur = [] }
            cur.append(d)
        }
        if !cur.isEmpty { out.append(cur) }
        return out
    }

    // Everything in the charts is the change since the first measurement in the range (kg), so ±1 kg is always visible
    // and fat/lean contributions are honest (no truncated axis exaggerating one of them).
    private func base(_ f: Field) -> Double { days.first { $0[f] != nil }?[f] ?? 0 }
    private var baseWeight: Double { base(.weightTrend) }
    private var baseLean: Double { base(.leanMassTrend) }
    private var baseFat: Double { base(.fatMassTrend) }
    private var baseMuscle: Double { base(.muscleTrend) }

    private var topDomain: ClosedRange<Double> {
        var vals: [Double] = [0]
        for d in days {
            if let w = d[.weightTrend] { vals.append(w - baseWeight) }
            if let w = d[.weight] { vals.append(w - baseWeight) }
            if let l = d[.leanMassTrend], let f = d[.fatMassTrend] { vals += [l - baseLean, l - baseLean + f - baseFat] }
        }
        let lo = vals.min() ?? 0, hi = vals.max() ?? 0
        let pad = max(0.4, (hi - lo) * 0.12)
        return (lo - pad)...(hi + pad)
    }

    private struct Tile: Identifiable {
        let title: String; let color: Color; let value: String; let delta: String?; let share: Double
        var id: String { title }
    }

    private var tiles: [Tile] {
        func firstLast(_ f: Field) -> (Double?, Double?) {
            (days.first { $0[f] != nil }?[f], days.last { $0[f] != nil }?[f])
        }
        func tile(_ title: String, _ color: Color, _ f: Field, share: Double = 0.2, suffix: (Double?) -> String = { _ in "" }) -> Tile {
            let (first, last) = firstLast(f)
            let shown = selected != nil ? selectedPoint?[f] : last
            let delta = (shown != nil && first != nil) ? String(format: "%+.1f", shown! - first!) : nil
            return Tile(title: title, color: color,
                        value: shown.map { String(format: "%.1f kg", $0) + suffix($0) } ?? "–", delta: delta, share: share)
        }
        let basis: DayPoint? = selected != nil ? selectedPoint : days.last { $0[.weightTrend] != nil }
        let pct: (Double?) -> String = { fat in
            guard let fat, let w = basis?[.weightTrend], w > 0 else { return "" }
            return String(format: " · %.1f %%", fat / w * 100)
        }
        return [tile("Weight", .primary, .weightTrend, share: 0.3),
                tile("Fat", fatColor, .fatMassTrend, share: 0.3, suffix: pct),
                tile("Lean", leanColor, .leanMassTrend),
                tile("Muscle", muscleColor, .muscleTrend)]
    }

    private var axis: (Calendar.Component, Int, Date.FormatStyle) { range.axisStride }

    // MARK: view

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Body composition", systemImage: "scalemass.fill").font(.headline)
                Spacer()
                Text(selected == nil ? "change over range" : "change vs. start of range")
                    .font(.caption).foregroundStyle(.secondary)
            }
            GeometryReader { g in
                HStack(alignment: .top, spacing: 8) {
                    ForEach(tiles) { t in
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) { Circle().fill(t.color).frame(width: 8, height: 8); Text(t.title).font(.caption).foregroundStyle(.secondary) }
                            Text(t.value).font(.subheadline.monospacedDigit().weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                                .contentTransition(.numericText())
                            Text(t.delta.map { "\($0) kg" } ?? " ").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        // widths 30 / 30 / 20 / 20 % (weight, fat, lean, muscle)
                        .frame(width: max(0, (g.size.width - 24) * t.share), alignment: .leading)
                    }
                }
            }
            .frame(height: 46)
            GeometryReader { g in
                VStack(spacing: 0) {
                    topChart.frame(height: g.size.height * 0.66)
                    bottomChart.frame(height: g.size.height * 0.34)
                }
            }
            HStack(spacing: 12) {
                legend(leanColor.opacity(0.5), "Lean mass change"); legend(fatColor.opacity(0.55), "Fat mass change")
                HStack(spacing: 5) { Capsule().fill(Color.primary.opacity(0.85)).frame(width: 16, height: 3); Text("Weight trend").font(.caption).foregroundStyle(.secondary) }
                HStack(spacing: 5) { Circle().fill(Color.secondary.opacity(0.6)).frame(width: 6, height: 6); Text("Daily weight").font(.caption).foregroundStyle(.secondary) }
            }
            Text("Top: kg change since the start of the range, split into lean and fat (the outer edge is your weight change). Trend = \(trendDays)-day exponential average. Fat/lean come from Garmin's body-fat estimate.")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func legend(_ c: Color, _ text: String) -> some View {
        HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(c).frame(width: 12, height: 12); Text(text).font(.caption).foregroundStyle(.secondary) }
    }

    private var x0: Date { window.start.addingTimeInterval(-43200) }
    private var x1: Date { window.end.addingTimeInterval(43200) }

    private func yAxis() -> some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
            AxisGridLine()
            AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: "%+.1f", d)).monospacedDigit().frame(width: 44, alignment: .leading) } }
        }
    }

    private var topChart: some View {
        let bW = baseWeight, bL = baseLean, bF = baseFat
        return Chart {
            ForEach(Array(segments.enumerated()), id: \.offset) { i, seg in
                ForEach(seg) { d in
                    if let l = d[.leanMassTrend], let f = d[.fatMassTrend] {
                        AreaMark(x: .value("Day", d.date), yStart: .value("Zero", 0.0), yEnd: .value("Lean", l - bL), series: .value("Lean", "lean\(i)"))
                            .foregroundStyle(leanColor.opacity(0.4))
                        AreaMark(x: .value("Day", d.date), yStart: .value("Lean", l - bL), yEnd: .value("Total", (l - bL) + (f - bF)), series: .value("Fat", "fat\(i)"))
                            .foregroundStyle(fatColor.opacity(0.5))
                    }
                }
            }
            RuleMark(y: .value("Start", 0.0)).foregroundStyle(.secondary.opacity(0.5)).lineStyle(StrokeStyle(lineWidth: 1))
            ForEach(days) { d in
                if let v = d[.weight] {
                    PointMark(x: .value("Day", d.date), y: .value("Weight", v - bW))
                        .foregroundStyle(Color.secondary.opacity(0.55)).symbolSize(days.count > 60 ? 8 : 22)
                }
            }
            ForEach(days) { d in
                if let t = d[.weightTrend] {
                    LineMark(x: .value("Day", d.date), y: .value("Trend", t - bW), series: .value("S", "trend"))
                        .foregroundStyle(Color.primary.opacity(0.85)).interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.8, lineCap: .round))
                }
            }
            if let sel = selected {
                RuleMark(x: .value("Selected", sel)).foregroundStyle(.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                if let t = selectedPoint?[.weightTrend] {
                    PointMark(x: .value("Day", sel), y: .value("Trend", t - bW)).foregroundStyle(Color.primary).symbolSize(120)
                }
            }
        }
        .chartXScale(domain: x0...x1)
        .chartYScale(domain: topDomain)
        .chartXAxis { AxisMarks(values: .stride(by: axis.0, count: axis.1)) { _ in AxisGridLine() } }
        .chartYAxis { yAxis() }
        .chartOverlay { proxy in DaySelectionOverlay(proxy: proxy, selected: $selected, window: window) }
        .overlay(alignment: .topLeading) {
            Text("Weight Δ kg").font(.caption2.weight(.bold)).foregroundStyle(.primary).padding(.leading, 6).padding(.top, 2)
        }
        .overlay {
            if segments.isEmpty && !days.contains(where: { $0[.weight] != nil }) {
                Text("No weight data from Garmin for this period.").font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 6)
    }

    private var bottomChart: some View {
        let (comp, count, fmt) = axis
        return Chart {
            ForEach(days) { d in
                if let v = d[.muscleMass] {
                    PointMark(x: .value("Day", d.date), y: .value("Muscle", v - baseMuscle))
                        .foregroundStyle(muscleColor.opacity(0.5)).symbolSize(days.count > 60 ? 8 : 22)
                }
            }
            ForEach(days) { d in
                if let t = d[.muscleTrend] {
                    LineMark(x: .value("Day", d.date), y: .value("Trend", t - baseMuscle), series: .value("S", "m"))
                        .foregroundStyle(muscleColor).interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2.8, lineCap: .round))
                }
            }
            if let sel = selected {
                RuleMark(x: .value("Selected", sel)).foregroundStyle(.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                if let t = selectedPoint?[.muscleTrend] {
                    PointMark(x: .value("Day", sel), y: .value("Trend", t - baseMuscle)).foregroundStyle(muscleColor).symbolSize(120)
                }
            }
        }
        .chartXScale(domain: x0...x1)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .stride(by: comp, count: count)) { _ in AxisGridLine(); AxisTick(); AxisValueLabel(format: fmt) }
        }
        .chartYAxis { yAxis() }
        .chartOverlay { proxy in DaySelectionOverlay(proxy: proxy, selected: $selected, window: window) }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Text("Muscle Δ kg").font(.caption2.weight(.bold)).foregroundStyle(muscleColor)
                if !days.contains(where: { $0[.muscleMass] != nil }) { Text("no data from Garmin").font(.caption2).foregroundStyle(.secondary) }
            }
            .padding(.leading, 6).padding(.top, 2)
        }
        .padding(.top, 6)
    }
}
