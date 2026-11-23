import SwiftUI

/// What the Garmin Personal API really provides for one night: bed/wake times, stage totals, awakenings and
/// Garmin's "ideal range" per stage. (It has no minute-by-minute stage data, so no hypnogram.)
struct NightDetailView: View {
    @Environment(DashboardStore.self) private var store
    let date: Date
    var height: CGFloat = 112

    private static let utc: DateFormatter = {
        let f = DateFormatter(); f.locale = .current; f.timeZone = TimeZone(identifier: "UTC"); f.dateFormat = "HH:mm"; return f
    }()

    private struct Stage { let name: String; let color: Color; let value: Double?; let lo: Double?; let hi: Double? }

    var body: some View {
        let d = store.days[date]
        Group {
            if let d, let asleep = d[.sleepHours] {
                content(d, asleep)
            } else {
                Text("No sleep recorded for this night.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: height)
    }

    private func clock(_ epoch: Double?) -> String? {
        epoch.map { Self.utc.string(from: Date(timeIntervalSince1970: $0)) }   // Garmin "local" stamps are wall-clock-as-UTC
    }

    @ViewBuilder private func content(_ d: DayPoint, _ asleep: Double) -> some View {
        let stages = [
            Stage(name: "Deep", color: .indigo, value: d[.sleepDeep], lo: d[.deepLo], hi: d[.deepHi]),
            Stage(name: "Light", color: .blue, value: d[.sleepLight], lo: d[.lightLo], hi: d[.lightHi]),
            Stage(name: "REM", color: .cyan, value: d[.sleepRem], lo: d[.remLo], hi: d[.remHi]),
        ]
        let awake = d[.sleepAwake] ?? 0
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                if let a = clock(d[.sleepStart]), let b = clock(d[.sleepEnd]) {
                    Label("\(a) – \(b)", systemImage: "moon.zzz").font(.caption.weight(.semibold))
                }
                Text("asleep \(Field.sleepHours.format(asleep))").font(.caption.monospacedDigit())
                Text("awake \(Field.sleepHours.format(awake))\(d[.awakeCount].map { " (\(Int($0))×)" } ?? "")")
                    .font(.caption.monospacedDigit()).foregroundStyle(.orange)
                Spacer()
            }
            .foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)

            // composition of the night, bar widths proportional to time
            GeometryReader { g in
                let total = max(0.01, asleep + awake)
                HStack(spacing: 1) {
                    ForEach(stages, id: \.name) { s in
                        if let v = s.value { RoundedRectangle(cornerRadius: 3).fill(s.color).frame(width: max(2, g.size.width * v / total)) }
                    }
                    if awake > 0 { RoundedRectangle(cornerRadius: 3).fill(Color.orange).frame(width: max(2, g.size.width * awake / total)) }
                }
            }
            .frame(height: 14)

            HStack(alignment: .top, spacing: 14) {
                ForEach(stages, id: \.name) { s in column(s, asleep: asleep) }
            }
        }
    }

    private func column(_ s: Stage, asleep: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Circle().fill(s.color).frame(width: 8, height: 8)
                Text(s.name).font(.caption.weight(.semibold))
                if let v = s.value {
                    Text("\(Field.sleepHours.format(v)) · \(Int((v / max(0.01, asleep) * 100).rounded())) %")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            .lineLimit(1).minimumScaleFactor(0.7)
            GeometryReader { g in
                let top = max(s.hi ?? 0, s.value ?? 0, 0.1) * 1.08
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.secondary.opacity(0.12))
                    if let lo = s.lo, let hi = s.hi {      // Garmin's ideal range for this stage
                        Rectangle().fill(s.color.opacity(0.28))
                            .frame(width: g.size.width * (hi - lo) / top).offset(x: g.size.width * lo / top)
                    }
                    if let v = s.value {
                        Capsule().fill(s.color).frame(width: max(3, g.size.width * v / top), height: 6)
                    }
                }
            }
            .frame(height: 12)
            if let lo = s.lo, let hi = s.hi {
                Text("ideal \(Field.sleepHours.format(lo)) – \(Field.sleepHours.format(hi))").font(.caption2).foregroundStyle(.secondary)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
