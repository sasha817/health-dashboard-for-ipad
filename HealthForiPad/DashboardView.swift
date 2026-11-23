import SwiftUI

enum Screen: String, CaseIterable, Identifiable {
    case vitals = "Vitals"
    case sleep = "Sleep"
    case body = "Body"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .vitals: "heart.text.square"
        case .sleep: "moon.zzz.fill"
        case .body: "scalemass"
        }
    }
}

struct DashboardView: View {
    @Environment(DashboardStore.self) private var store
    @State private var screen: Screen = .vitals
    @State private var showSettings = false

    private let railWidth: CGFloat = 92

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                let landscape = geo.size.width > geo.size.height
                HStack(spacing: 0) {
                    if landscape { rail }
                    content(width: geo.size.width - (landscape ? railWidth : 0), height: geo.size.height, landscape: landscape)
                }
                .overlay(alignment: .bottom) { if !landscape { floatingTabs.padding(.bottom, 10) } }
            }
            .navigationTitle(screen.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Range", selection: Binding(get: { store.range }, set: { store.setRange($0) })) {
                        ForEach(store.availableRanges) { Text($0.short).tag($0) }
                    }.pickerStyle(.segmented).frame(width: store.availableRanges.count > 5 ? 390 : 330)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if store.isLoading || store.backfillProgress != nil { ProgressView() }
                    Button { Task { await store.load(manual: true) } } label: { Image(systemName: "arrow.clockwise") }
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .task {
                if store.needsSetup { showSettings = true } else { await store.load() }
            }
        }
    }

    // MARK: navigation

    private var rail: some View {
        VStack(spacing: 14) {
            ForEach(Screen.allCases) { s in
                Button { withAnimation(.snappy) { screen = s } } label: {
                    VStack(spacing: 5) {
                        Image(systemName: s.icon).font(.system(size: 26))
                        Text(s.rawValue).font(.caption.weight(.medium))
                    }
                    .frame(width: 72, height: 66)
                    .foregroundStyle(screen == s ? Color.accentColor : .secondary)
                    .background(screen == s ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 14)
        .frame(width: railWidth)
        .frame(maxHeight: .infinity)
        .background(.bar)
    }

    private var floatingTabs: some View {
        HStack(spacing: 6) {
            ForEach(Screen.allCases) { s in
                Button { withAnimation(.snappy) { screen = s } } label: {
                    Label(s.rawValue, systemImage: s.icon)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18).padding(.vertical, 10)
                        .foregroundStyle(screen == s ? Color.white : .primary)
                        .background(screen == s ? Color.accentColor : .clear, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .shadow(radius: 6, y: 2)
    }

    // MARK: content

    private func content(width: CGFloat, height: CGFloat, landscape: Bool) -> some View {
        @Bindable var store = store
        let days = store.visible
        let cs = cards(for: screen)
        let pad: CGFloat = 14, gap: CGFloat = 12
        let statusH: CGFloat = 34
        @ViewBuilder func card(_ c: Card, _ h: CGFloat) -> some View {
            if c.bodyComp {
                BodyCompositionCard(days: days, range: store.range, window: store.window,
                                    selected: $store.selected, trendDays: store.effectiveRollingDays)
                    .frame(height: h)
            } else {
            ChartCard(title: c.title, icon: c.icon, series: c.series, days: days,
                      range: store.range, window: store.window,
                      selected: $store.selected, yIncludesZero: c.zero, emptyNote: c.note,
                      goal: c.goal, zones: c.zones,
                      yDomain: c.domain ?? (c.zones.isEmpty ? nil : bpDomain(days)), footnote: c.footnote,
                      extra: (c.nightDetail && store.selected != nil) ? AnyView(NightDetailView(date: store.selected!, height: screen == .sleep ? 150 : 112)) : nil,
                      stages: c.stages)
                .frame(height: h)
            }
        }
        return ScrollView {
            VStack(spacing: gap) {
                statusBar.frame(minHeight: statusH)
                if landscape {
                    let avail = height - pad * 2 - statusH - gap - 8
                    let rowH = (avail - gap) / 2
                    if screen == .sleep && cs.count == 5 {
                        let top = (avail - gap) * 0.58, bottom = (avail - gap) - top
                        let scoreW = (width - 32 - gap) * 0.33
                        VStack(spacing: gap) {
                            HStack(spacing: gap) { card(cs[0], top); card(cs[1], top).frame(width: scoreW) }
                            HStack(spacing: gap) { card(cs[2], bottom); card(cs[3], bottom); card(cs[4], bottom) }
                        }
                    } else if cs.count >= 4 {
                        VStack(spacing: gap) {
                            HStack(spacing: gap) { card(cs[0], rowH); card(cs[1], rowH) }
                            HStack(spacing: gap) { card(cs[2], rowH); card(cs[3], rowH) }
                        }
                    } else {
                        HStack(spacing: gap) {
                            card(cs[0], avail)
                            VStack(spacing: gap) { card(cs[1], rowH); card(cs[2], rowH) }
                        }
                    }
                } else {
                    let h = max(210, (height - 110) / 3 - 14)
                    ForEach(cs, id: \.title) { c in card(c, h) }
                    Color.clear.frame(height: 56)   // room for the floating tab bar
                }
            }
            .padding(.horizontal, 16).padding(.vertical, pad)
        }
        .refreshable { await store.load(manual: true) }
    }

    @ViewBuilder private var statusBar: some View {
        @Bindable var store = store
        HStack {
            if let s = store.selected {
                Image(systemName: "hand.tap.fill").foregroundStyle(.tint)
                Text(s.formatted(.dateTime.weekday(.wide).day().month(.wide).year())).font(.headline)
                Button("Clear") { withAnimation { store.selected = nil } }.buttonStyle(.bordered).controlSize(.small)
            } else {
                Image(systemName: "hand.tap").foregroundStyle(.secondary)
                Text("Touch and hold a chart, then drag to inspect a day. Without a selection, values show the period average.")
                    .font(.subheadline).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            Spacer()
            if store.useDemo { Text("DEMO DATA").font(.caption.bold()).padding(5).background(.orange.opacity(0.2), in: Capsule()) }
        }
        if let e = store.errorMessage {
            Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
        } else if !store.warnings.isEmpty {
            Label(store.warnings.joined(separator: "  ·  "), systemImage: "exclamationmark.circle")
                .font(.caption).foregroundStyle(.orange).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: chart definitions

    struct Card {
        let title: String; let icon: String; let series: [Series]
        var zero = false; var note: String? = nil; var goal: Goal? = nil
        var zones: [Zone] = []; var footnote: String? = nil; var stages: [Series] = []; var nightDetail = false
        var bodyComp = false; var domain: ClosedRange<Double>? = nil
    }

    private func bpDomain(_ days: [DayPoint]) -> ClosedRange<Double> {
        let lo = days.compactMap { $0[.diastolic] }.min() ?? 70
        let hi = days.compactMap { $0[.systolic] }.max() ?? 130
        return min(60, (lo - 5).rounded(.down))...max(150, (hi + 5).rounded(.up))
    }

    private var rhrSeries: [Series] {
        [Series(field: .rhr, color: .red, tag: "daily", lineWidth: 1.8, opacity: 0.55),
         Series(field: .rhrAvg, color: Color(red: 0.62, green: 0.05, blue: 0.1), tag: "\(store.effectiveRollingDays)-day avg", lineWidth: 3.5, points: false, rolling: true)]
    }

    private var sleepStageCard: Card {
        Card(title: "Sleep", icon: "bed.double.fill", series: [Series(field: .sleepHours, color: .indigo, bars: true)], zero: true,
             goal: Goal(value: store.sleepGoal, label: "Goal \(Field.sleepHours.format(store.sleepGoal))", color: .mint),
             stages: [Series(field: .sleepDeep, color: .indigo, bars: true, tag: "Deep"),
                      Series(field: .sleepLight, color: .blue, bars: true, tag: "Light"),
                      Series(field: .sleepRem, color: .cyan, bars: true, tag: "REM"),
                      Series(field: .sleepAwake, color: .orange, bars: true, tag: "Awake")],
             nightDetail: true)
    }

    // Garmin sleep score bands
    private let scoreZones: [Zone] = [
        Zone(from: 0, to: 60, color: .red), Zone(from: 60, to: 80, color: .orange),
        Zone(from: 80, to: 90, color: .yellow), Zone(from: 90, to: 101, color: .green),
    ]

    private var stressCard: Card { Card(title: "Stress", icon: "brain.head.profile", series: [Series(field: .stress, color: .orange)]) }

    private func cards(for s: Screen) -> [Card] {
        switch s {
        case .vitals: [
            Card(title: "Resting heart rate", icon: "heart.fill", series: rhrSeries),
            sleepStageCard,
            Card(title: "Blood pressure", icon: "waveform.path.ecg",
                 series: [Series(field: .systolic, color: .purple, tag: "sys"), Series(field: .diastolic, color: .blue, tag: "dia")],
                 note: store.useHealthKit ? "No blood pressure readings in Apple Health for this period." : "Garmin's Personal API has no blood pressure data. Connect Apple Health in Settings.",
                 zones: store.bpGuideline.zones, footnote: store.bpGuideline.legend),
            stressCard,
        ]
        case .sleep: [
            sleepStageCard,
            Card(title: "Sleep score", icon: "sparkles", series: [Series(field: .sleepScore, color: .indigo)],
                 zones: scoreZones, footnote: "poor <60 · fair 60–79 · good 80–89 · excellent 90+", domain: 40...100),
            Card(title: "SpO₂", icon: "lungs.fill",
                 series: [Series(field: .spo2Avg, color: .blue, tag: "avg"),
                          Series(field: .spo2Low, color: .cyan, tag: "lowest", opacity: 0.8)]),
            Card(title: "Respiration", icon: "wind", series: [Series(field: .respAvg, color: .teal)]),
            Card(title: "HR/stress", icon: "waveform.path.ecg.rectangle",
                 series: [Series(field: .sleepHR, color: .red, tag: "HR"), Series(field: .sleepStress, color: .orange, tag: "stress")]),
        ]
        case .body: [
            Card(title: "Body composition", icon: "scalemass.fill", series: [], bodyComp: true),
            Card(title: "Resting heart rate", icon: "heart.fill", series: rhrSeries),
            stressCard,
        ]
        }
    }
}
