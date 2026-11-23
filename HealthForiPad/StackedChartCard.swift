import SwiftUI
import Charts

/// One panel of a stacked card: raw measurements plus their rolling average, with its own y scale.
struct Panel: Identifiable {
    let raw: Field
    let avg: Field
    let color: Color
    let title: String
    var tag = ""
    var format = "%.1f"
    var id: Field { raw }
}

/// Several charts stacked into one card (shared x axis and day selection), e.g. weight / body fat / muscle.
struct StackedChartCard: View {
    let title: String
    let icon: String
    let panels: [Panel]
    let days: [DayPoint]
    let range: TimeRange
    let window: (start: Date, end: Date)
    @Binding var selected: Date?
    var emptyNote = "No data for this period."

    private var selectedPoint: DayPoint? { selected.flatMap { s in days.first { $0.date == s } } }

    private func headerValue(_ f: Field, latest: Bool) -> Double? {
        if selected != nil { return selectedPoint?[f] }
        let v = days.compactMap { $0[f] }
        return latest ? v.last : (v.isEmpty ? nil : v.reduce(0, +) / Double(v.count))
    }

    private var axis: (Calendar.Component, Int, Date.FormatStyle) {
        switch range {
        case .week: (.day, 1, .dateTime.weekday(.abbreviated))
        case .month: (.day, 7, .dateTime.day().month(.abbreviated))
        case .quarter: (.day, 14, .dateTime.day().month(.abbreviated))
        case .half: (.month, 1, .dateTime.month(.abbreviated))
        case .year: (.month, 2, .dateTime.month(.abbreviated))
        case .twoYears: (.month, 4, .dateTime.month(.abbreviated).year(.twoDigits))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Label(title, systemImage: icon).font(.headline)
                Spacer()
                ForEach(panels) { p in
                    HStack(spacing: 4) {
                        Circle().fill(p.color).frame(width: 9, height: 9)
                        Text(p.tag).font(.caption).foregroundStyle(.secondary)
                        Text(headerValue(p.raw, latest: false).map { p.raw.format($0) } ?? "–")
                            .font(.title3.monospacedDigit().weight(.semibold))
                            .contentTransition(.numericText())
                    }
                }
                if selected == nil { Text("avg").font(.caption).foregroundStyle(.secondary) }
            }
            .lineLimit(1).minimumScaleFactor(0.7)

            VStack(spacing: 0) {
                ForEach(Array(panels.enumerated()), id: \.element.id) { i, p in
                    panel(p, last: i == panels.count - 1)
                    if i < panels.count - 1 { Divider() }
                }
            }
        }
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16))
    }

    private func panel(_ p: Panel, last: Bool) -> some View {
        let (comp, count, fmt) = axis
        let x0 = window.start.addingTimeInterval(-43200), x1 = window.end.addingTimeInterval(43200)
        let hasData = days.contains { $0[p.raw] != nil }
        return Chart {
            ForEach(days) { d in
                if let v = d[p.raw] {
                    LineMark(x: .value("Day", d.date), y: .value(p.title, v), series: .value("S", "raw"))
                        .foregroundStyle(p.color.opacity(0.45)).lineStyle(StrokeStyle(lineWidth: 1.3))
                    PointMark(x: .value("Day", d.date), y: .value(p.title, v))
                        .foregroundStyle(p.color.opacity(0.7)).symbolSize(days.count > 60 ? 12 : 28)
                }
            }
            ForEach(days) { d in
                if let a = d[p.avg] {
                    LineMark(x: .value("Day", d.date), y: .value("Avg", a), series: .value("S", "avg"))
                        .foregroundStyle(p.color).interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                }
            }
            if let sel = selected {
                RuleMark(x: .value("Selected", sel))
                    .foregroundStyle(.secondary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                if let v = selectedPoint?[p.raw] ?? selectedPoint?[p.avg] {
                    PointMark(x: .value("Day", sel), y: .value(p.title, v)).foregroundStyle(p.color).symbolSize(130)
                }
            }
        }
        .chartXScale(domain: x0...x1)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .stride(by: comp, count: count)) { _ in
                AxisGridLine()
                if last { AxisTick(); AxisValueLabel(format: fmt) }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine()
                // fixed label width keeps every panel's plot area identical, so one touch maps to the same day in all panels
                AxisValueLabel { if let d = v.as(Double.self) { Text(String(format: "%.0f", d)).monospacedDigit().frame(width: 40, alignment: .leading) } }
            }
        }
        .chartOverlay { proxy in DaySelectionOverlay(proxy: proxy, selected: $selected, window: window) }
        .overlay(alignment: .topLeading) {
            HStack(spacing: 6) {
                Text(p.title).font(.caption2.weight(.bold)).foregroundStyle(p.color)
                if !hasData { Text(emptyNote).font(.caption2).foregroundStyle(.secondary) }
            }
            .padding(.leading, 6).padding(.top, 2)
        }
        .padding(.vertical, 7)
        .frame(maxHeight: .infinity)
    }
}
