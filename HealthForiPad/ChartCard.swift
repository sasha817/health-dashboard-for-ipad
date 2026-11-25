import SwiftUI
import Charts
import UIKit

struct Series: Identifiable {
    let field: Field
    let color: Color
    var bars = false
    var tag: String? = nil          // short caption shown before the header value
    var lineWidth: CGFloat = 2.5
    var opacity: Double = 1
    var points = true
    var rolling = false             // header shows the latest value instead of the period average
    var id: Field { field }
}

struct Zone: Identifiable {
    let from: Double, to: Double
    let color: Color
    var id: Double { from }
}

struct Goal {
    let value: Double
    let label: String
    let color: Color
}

struct ChartCard: View {
    let title: String
    let icon: String
    let series: [Series]
    let days: [DayPoint]
    let range: TimeRange
    let window: (start: Date, end: Date)
    @Binding var selected: Date?
    var yIncludesZero = false
    var emptyNote: String? = nil
    var goal: Goal? = nil
    var zones: [Zone] = []
    var yDomain: ClosedRange<Double>? = nil
    var footnote: String? = nil
    var extra: AnyView? = nil         // e.g. the sleep timeline of the selected night, shown under the chart
    var stages: [Series] = []        // stacked sleep stages (bottom → top); days without stage data fall back to `series` bars

    private var selectedPoint: DayPoint? { selected.flatMap { s in days.first { $0.date == s } } }

    private func hasStages(_ d: DayPoint) -> Bool { stages.contains { d[$0.field] != nil } }
    private var anyStages: Bool { days.contains(where: hasStages) }
    private var headerSeries: [Series] {
        series + (selected != nil && extra == nil ? stages.filter { selectedPoint?[$0.field] != nil } : [])
    }

    private func headerValue(_ s: Series) -> Double? {
        if selected != nil { return selectedPoint?[s.field] }
        let v = days.compactMap { $0[s.field] }
        if s.rolling { return v.last }
        return v.isEmpty ? nil : v.reduce(0, +) / Double(v.count)
    }

    private var axisStride: (Calendar.Component, Int, Date.FormatStyle) { range.axisStride }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Label(title, systemImage: icon).font(.headline)
                Spacer()
                ForEach(headerSeries) { s in
                    let v = headerValue(s)
                    HStack(spacing: 4) {
                        Circle().fill(s.color.opacity(s.opacity)).frame(width: 9, height: 9)
                        if let t = s.tag { Text(t).font(.caption).foregroundStyle(.secondary) }
                        Text(v.map { s.field.format($0) } ?? "–")
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .contentTransition(.numericText())
                    }
                }
                if selected == nil { Text("avg").font(.caption).foregroundStyle(.secondary) }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            chart
                .overlay {
                    if let n = emptyNote, !days.contains(where: { d in series.contains { d[$0.field] != nil } }) {
                        Text(n).font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                    }
                }
            if let e = extra { e.transition(.opacity) }
            if anyStages || goal != nil {
                HStack(spacing: 14) {
                    if anyStages && extra == nil {
                        ForEach(stages.reversed()) { s in
                            HStack(spacing: 5) { RoundedRectangle(cornerRadius: 2).fill(s.color).frame(width: 12, height: 12)
                                Text(s.field.label).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if let g = goal {
                        HStack(spacing: 5) {
                            Rectangle().fill(g.color).frame(width: 18, height: 2)
                            Text(anyStages ? "\(g.label) (time asleep, without awake)" : g.label).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let f = footnote { Text(f).font(.caption).foregroundStyle(.secondary) }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder private func applyY<V: View>(_ v: V) -> some View {
        if let r = yDomain { v.chartYScale(domain: r) }
        else { v.chartYScale(domain: .automatic(includesZero: yIncludesZero)) }
    }

    private var chart: some View {
        let (comp, count, fmt) = axisStride
        let x0 = window.start.addingTimeInterval(-43200), x1 = window.end.addingTimeInterval(43200)
        return applyY(Chart {
            // blood-pressure style background zones (behind everything)
            ForEach(zones) { z in
                let lo = max(z.from, yDomain?.lowerBound ?? z.from), hi = min(z.to, yDomain?.upperBound ?? z.to)
                if hi > lo {
                    RectangleMark(xStart: .value("s", x0), xEnd: .value("e", x1),
                                  yStart: .value("z0", lo), yEnd: .value("z1", hi))
                        .foregroundStyle(z.color.opacity(0.17))
                }
            }
            if let g = goal {
                RuleMark(y: .value("Goal", g.value))
                    .foregroundStyle(g.color)
                    .lineStyle(StrokeStyle(lineWidth: 1.8, dash: [7, 5]))
            }
            ForEach(series) { s in
                ForEach(days) { d in
                    if let v = d[s.field] {
                        if s.bars {
                            if !hasStages(d) {
                                BarMark(x: .value("Day", d.date, unit: .day), y: .value(s.field.label, v))
                                    .foregroundStyle(s.color.opacity(selected == nil || selected == d.date ? 0.85 : 0.35))
                            }
                        } else {
                            LineMark(x: .value("Day", d.date), y: .value(s.field.label, v), series: .value("Series", s.field.label))
                                .foregroundStyle(s.color.opacity(s.opacity))
                                .interpolationMethod(.monotone)
                                .lineStyle(StrokeStyle(lineWidth: s.lineWidth, lineCap: .round))
                            if s.points && (days.count <= 40 || range == .week) {
                                PointMark(x: .value("Day", d.date), y: .value(s.field.label, v))
                                    .foregroundStyle(s.color.opacity(s.opacity)).symbolSize(range == .week ? 50 : 20)
                            }
                        }
                    }
                }
            }
            ForEach(stages) { s in
                ForEach(days) { d in
                    if let v = d[s.field] {
                        BarMark(x: .value("Day", d.date, unit: .day), y: .value(s.field.label, v))
                            .foregroundStyle(by: .value("Stage", s.field.label))
                            .opacity(selected == nil || selected == d.date ? 1 : 0.4)
                    }
                }
            }
            if let sel = selected {
                RuleMark(x: .value("Selected", sel))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                if let p = selectedPoint {
                    ForEach(series.filter { !$0.bars }) { s in
                        if let v = p[s.field] {
                            PointMark(x: .value("Day", sel), y: .value(s.field.label, v))
                                .foregroundStyle(s.color).symbolSize(150)
                        }
                    }
                }
            }
        })
        .chartForegroundStyleScale(domain: stages.map { $0.field.label }, range: stages.map { $0.color })
        .chartLegend(.hidden)
        .chartXScale(domain: x0...x1)
        .chartXAxis {
            AxisMarks(values: .stride(by: comp, count: count)) { _ in
                AxisGridLine(); AxisTick(); AxisValueLabel(format: fmt)
            }
        }
        .chartOverlay { proxy in DaySelectionOverlay(proxy: proxy, selected: $selected, window: window) }
    }
}

/// Touch-and-hold, then drag: snaps `selected` to the nearest day under the finger. Shared by all charts.
struct DaySelectionOverlay: View {
    let proxy: ChartProxy
    @Binding var selected: Date?
    let window: (start: Date, end: Date)

    var body: some View {
        GeometryReader { geo in
            Rectangle().fill(.clear).contentShape(Rectangle())
                .onTapGesture { withAnimation(.snappy) { selected = nil } }
                .gesture(
                    LongPressGesture(minimumDuration: 0.25)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                        .onChanged { value in
                            guard case .second(true, let drag) = value, let drag, let frame = proxy.plotFrame else { return }
                            let x = drag.location.x - geo[frame].origin.x
                            guard let date: Date = proxy.value(atX: x) else { return }
                            var day = Cal.noon(date)
                            day = min(max(day, window.start), window.end)
                            if day != selected {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.snappy(duration: 0.15)) { selected = day }
                            }
                        }
                )
        }
    }
}
