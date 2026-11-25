import SwiftUI
import Charts

/// Systolic (top) and diastolic (bottom) in two panels, each with its *own* correct zone bands.
/// Per day: a bar from the lowest to the highest reading and a dot at the average, coloured by that panel's category.
struct BloodPressureCard: View {
    let days: [DayPoint]
    let range: TimeRange
    let window: (start: Date, end: Date)
    @Binding var selected: Date?
    let guideline: BPGuideline
    let emptyNote: String

    private struct Spec {
        let title: String; let avg: Field; let lo: Field; let hi: Field
        let zones: [Zone]; let limits: [Double]; let category: (Double) -> Int; let fallback: ClosedRange<Double>
    }
    private var sysSpec: Spec { Spec(title: "Systolic", avg: .systolic, lo: .sysMin, hi: .sysMax, zones: guideline.sysZones, limits: guideline.sysLimits, category: guideline.sysCategory, fallback: 100...150) }
    private var diaSpec: Spec { Spec(title: "Diastolic", avg: .diastolic, lo: .diaMin, hi: .diaMax, zones: guideline.diaZones, limits: guideline.diaLimits, category: guideline.diaCategory, fallback: 60...100) }

    private var selectedPoint: DayPoint? { selected.flatMap { s in days.first { $0.date == s } } }
    private var hasData: Bool { days.contains { $0[.systolic] != nil } }

    /// Values shown in the header: the selected day, otherwise the average over the range.
    private var shown: (sys: Double, dia: Double)? {
        if selected != nil {
            guard let p = selectedPoint, let s = p[.systolic], let d = p[.diastolic] else { return nil }
            return (s, d)
        }
        let s = days.compactMap { $0[.systolic] }, d = days.compactMap { $0[.diastolic] }
        guard !s.isEmpty, !d.isEmpty else { return nil }
        return (s.reduce(0, +) / Double(s.count), d.reduce(0, +) / Double(d.count))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Label("Blood pressure", systemImage: "waveform.path.ecg").font(.headline)
                Spacer()
                if let v = shown {
                    let cat = guideline.category(sys: v.sys, dia: v.dia)
                    Text(guideline.categoryNames[cat]).font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(BPGuideline.zoneColors[cat].opacity(0.35), in: Capsule())
                    Text(String(format: "%.0f / %.0f", v.sys, v.dia)).font(.title3.monospacedDigit().weight(.semibold))
                        .contentTransition(.numericText())
                    Text("mmHg" + (selected == nil ? " avg" : "")).font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("–").font(.title3).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.7)

            GeometryReader { g in
                VStack(spacing: 0) {
                    panel(sysSpec, last: false).frame(height: g.size.height * 0.5)
                    panel(diaSpec, last: true).frame(height: g.size.height * 0.5)
                }
            }
            Text("Zones: \(guideline == .aha ? "AHA" : "ESC") · bar = day's lowest–highest, dot = average")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func domain(_ s: Spec) -> ClosedRange<Double> {
        let vals = days.flatMap { [$0[s.lo], $0[s.hi], $0[s.avg]] }.compactMap { $0 }
        guard let mn = vals.min(), let mx = vals.max() else { return s.fallback }
        return floor(min(s.fallback.lowerBound, mn - 4))...ceil(max(s.fallback.upperBound, mx + 4))
    }

    private func panel(_ s: Spec, last: Bool) -> some View {
        let dom = domain(s)
        let (comp, count, fmt) = range.axisStride
        let x0 = window.start.addingTimeInterval(-43200), x1 = window.end.addingTimeInterval(43200)
        let dense = days.count > 60
        // y labels sit on the zone limits, never on the panel edges, so the two panels can touch without labels colliding
        let ticks = Array(Set(s.limits)).sorted().filter { $0 > dom.lowerBound + 3 && $0 < dom.upperBound - 3 }
        return Chart {
            ForEach(s.zones) { z in
                let lo = max(z.from, dom.lowerBound), hi = min(z.to, dom.upperBound)
                if hi > lo {
                    RectangleMark(xStart: .value("s", x0), xEnd: .value("e", x1), yStart: .value("z0", lo), yEnd: .value("z1", hi))
                        .foregroundStyle(z.color.opacity(0.17))
                }
            }
            ForEach(days) { d in
                if let a = d[s.avg] {
                    let color = BPGuideline.markerColors[s.category(a)]
                    if let mn = d[s.lo], let mx = d[s.hi], mx > mn {
                        RuleMark(x: .value("Day", d.date), yStart: .value("Min", mn), yEnd: .value("Max", mx))
                            .foregroundStyle(color.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: dense ? 2 : 6, lineCap: .round))
                    }
                    PointMark(x: .value("Day", d.date), y: .value(s.title, a))
                        .foregroundStyle(color).symbolSize(dense ? 14 : 46)
                }
            }
            if let sel = selected {
                RuleMark(x: .value("Selected", sel)).foregroundStyle(.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                if let a = selectedPoint?[s.avg] {
                    PointMark(x: .value("Day", sel), y: .value(s.title, a)).foregroundStyle(Color.primary).symbolSize(110)
                }
            }
        }
        .chartXScale(domain: x0...x1)
        .chartYScale(domain: dom)
        .chartXAxis {
            AxisMarks(values: .stride(by: comp, count: count)) { _ in
                AxisGridLine()
                if last { AxisTick(); AxisValueLabel(format: fmt) }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: ticks) { v in
                AxisGridLine()
                AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: "%.0f", d)).monospacedDigit().frame(width: 40, alignment: .leading) } }
            }
        }
        .chartOverlay { proxy in DaySelectionOverlay(proxy: proxy, selected: $selected, window: window) }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Text(s.title).font(.caption2.weight(.bold))
                if !hasData { Text(emptyNote).font(.caption2).foregroundStyle(.secondary) }
            }
            .padding(.leading, 6).padding(.top, 2)
        }
        .padding(.vertical, 2)
    }
}

/// "Blood pressure map": every day as a dot (diastolic across, systolic up) on the classification regions.
/// This is the one picture where the combined category is exact, because each region is bounded by both limits.
struct BloodPressureMapCard: View {
    let days: [DayPoint]
    let readings: [BPReading]
    let window: (start: Date, end: Date)
    @Binding var selected: Date?
    let guideline: BPGuideline
    let emptyNote: String

    /// Every measurement in the range, oldest first. If Apple Health returned no individual readings (only daily
    /// statistics), the daily averages are shown instead.
    private var points: [BPReading] {
        let inRange = readings.filter { $0.day >= window.start && $0.day <= window.end }
        if !inRange.isEmpty { return inRange.sorted { $0.time < $1.time } }
        return days.compactMap { d in
            guard let s = d[.systolic], let di = d[.diastolic] else { return nil }
            return BPReading(time: d.date, sys: s, dia: di)
        }
    }
    private var selectedReadings: [BPReading] { selected.map { sel in points.filter { $0.day == sel } } ?? [] }

    private var xr: ClosedRange<Double> {
        let v = points.map(\.dia)
        return floor(min(55, (v.min() ?? 60) - 4))...ceil(max(100, (v.max() ?? 90) + 4))
    }
    private var yr: ClosedRange<Double> {
        let v = points.map(\.sys)
        return floor(min(95, (v.min() ?? 100) - 5))...ceil(max(150, (v.max() ?? 130) + 5))
    }

    /// Region of category k = rect(k) minus rect(k-1), where rect(k) lies below both limits of category k.
    /// Drawn as up to two disjoint rectangles so translucent colours never stack.
    private func rects(for k: Int) -> [(x0: Double, x1: Double, y0: Double, y1: Double)] {
        let X = xr, Y = yr
        func lim(_ arr: [Double], _ i: Int, _ hi: Double) -> Double { i < arr.count ? arr[i] : hi }
        let dk = lim(guideline.diaLimits, k, X.upperBound), sk = lim(guideline.sysLimits, k, Y.upperBound)
        guard k > 0 else { return [(X.lowerBound, dk, Y.lowerBound, sk)] }
        let dp = guideline.diaLimits[k - 1], sp = guideline.sysLimits[k - 1]
        var out: [(Double, Double, Double, Double)] = []
        if dk > dp { out.append((dp, dk, Y.lowerBound, sk)) }                // to the right of the previous region
        if sk > sp { out.append((X.lowerBound, min(dp, dk), sp, sk)) }       // above the previous region
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Label("Blood pressure map", systemImage: "scope").font(.headline)
                Spacer()
                let sel = selectedReadings
                if !sel.isEmpty {
                    let s = sel.map(\.sys).reduce(0, +) / Double(sel.count), d = sel.map(\.dia).reduce(0, +) / Double(sel.count)
                    let cat = guideline.category(sys: s, dia: d)
                    Text(guideline.categoryNames[cat]).font(.caption.weight(.semibold))
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(BPGuideline.zoneColors[cat].opacity(0.35), in: Capsule())
                    Text(String(format: "%.0f / %.0f", s, d)).font(.title3.monospacedDigit().weight(.semibold))
                    Text(sel.count == 1 ? "1 reading" : "\(sel.count) readings · avg").font(.caption).foregroundStyle(.secondary)
                } else {
                }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            .frame(height: 30)
            // the chart gets exactly the height that is left; its own minimum size can never push it over the header
            GeometryReader { g in
                chart.frame(width: g.size.width, height: g.size.height).clipped()
            }
            .clipped()
            Text("\(guideline == .aha ? "AHA" : "ESC") regions · each dot = one reading · darker dots = more recent")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private var chart: some View {
        let pts = points
        let n = max(1, pts.count - 1)
        return Chart {
            ForEach(0..<4, id: \.self) { k in
                ForEach(Array(rects(for: k).enumerated()), id: \.offset) { _, r in
                    RectangleMark(xStart: .value("x0", r.x0), xEnd: .value("x1", r.x1), yStart: .value("y0", r.y0), yEnd: .value("y1", r.y1))
                        .foregroundStyle(BPGuideline.zoneColors[k].opacity(0.2))
                }
            }
            ForEach(Array(pts.enumerated()), id: \.element.id) { i, r in
                PointMark(x: .value("Diastolic", r.dia), y: .value("Systolic", r.sys))
                    .foregroundStyle(Color.primary.opacity(0.18 + 0.72 * Double(i) / Double(n)))
                    .symbolSize(pts.count > 300 ? 10 : pts.count > 100 ? 16 : 34)
            }
            ForEach(selectedReadings) { r in
                PointMark(x: .value("Diastolic", r.dia), y: .value("Systolic", r.sys)).foregroundStyle(Color.primary).symbolSize(190)
                PointMark(x: .value("Diastolic", r.dia), y: .value("Systolic", r.sys)).foregroundStyle(Color.white).symbolSize(50)
            }
        }
        .chartXScale(domain: xr)
        .chartYScale(domain: yr)
        .chartPlotStyle { $0.clipped() }
        .chartXAxisLabel("Diastolic mmHg", alignment: .center)
        .chartYAxisLabel("Systolic mmHg", position: .trailing)
        .chartOverlay { proxy in
            GeometryReader { geo in
                Rectangle().fill(.clear).contentShape(Rectangle())
                    .onTapGesture { withAnimation(.snappy) { selected = nil } }
                    .gesture(
                        LongPressGesture(minimumDuration: 0.25)
                            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                            .onChanged { value in
                                guard case .second(true, let drag) = value, let drag, let frame = proxy.plotFrame else { return }
                                let o = geo[frame].origin
                                guard let (dia, sys) = proxy.value(at: CGPoint(x: drag.location.x - o.x, y: drag.location.y - o.y), as: (Double, Double).self) else { return }
                                // nearest day in (normalised) map coordinates
                                let wx = xr.upperBound - xr.lowerBound, wy = yr.upperBound - yr.lowerBound
                                let best = points.min { a, b in
                                    func dist(_ p: BPReading) -> Double { pow((p.dia - dia) / wx, 2) + pow((p.sys - sys) / wy, 2) }
                                    return dist(a) < dist(b)
                                }
                                if let best, best.day != selected {
                                    UISelectionFeedbackGenerator().selectionChanged()
                                    withAnimation(.snappy(duration: 0.15)) { selected = best.day }
                                }
                            }
                    )
            }
        }
        .overlay {
            if pts.isEmpty { Text(emptyNote).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding() }
        }
    }
}
