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
                // landscape: no navigation bar at all, its controls live in the rail
                .toolbar(landscape ? .hidden : .visible, for: .navigationBar)
                .overlay(alignment: .top) { if landscape && screen == .body { selectionChip.padding(.top, 6) } }
                .overlay(alignment: .bottom) { if !landscape { floatingTabs.padding(.bottom, 10) } }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 8) {
                        if let s = store.selected {
                            Image(systemName: "hand.tap.fill").foregroundStyle(.tint)
                            Text(s.shortDayLabel).font(.headline)
                            Button("Clear") { withAnimation { store.selected = nil } }.buttonStyle(.bordered).controlSize(.small)
                        } else {
                            Text(screen.rawValue).font(.headline)
                        }
                        if store.useDemo { Text("DEMO").font(.caption2.bold()).padding(4).background(.orange.opacity(0.25), in: Capsule()) }
                    }
                }
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
            if store.useDemo { Text("DEMO").font(.caption2.bold()).padding(4).background(.orange.opacity(0.25), in: Capsule()) }
            VStack(spacing: 4) {
                ForEach(store.availableRanges) { r in
                    Button { store.setRange(r) } label: {
                        Text(r.short).font(.subheadline.weight(.semibold))
                            .frame(width: 66, height: 32)
                            .foregroundStyle(store.range == r ? Color.white : .primary)
                            .background(store.range == r ? Color.accentColor : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain)
                }
            }
            if store.isLoading || store.backfillProgress != nil { ProgressView() }
            HStack(spacing: 4) {
                Button { Task { await store.load(manual: true) } } label: { Image(systemName: "arrow.clockwise").frame(width: 36, height: 36) }
                Button { showSettings = true } label: { Image(systemName: "gearshape").frame(width: 36, height: 36) }
            }
            .padding(.bottom, 12)
        }
        .padding(.top, 14)
        .frame(width: railWidth)
        .frame(maxHeight: .infinity)
        .background(.bar)
    }

    /// Selected day (landscape): a small floating chip instead of a permanent status row.
    @ViewBuilder private var selectionChip: some View {
        if let sel = store.selected {
            HStack(spacing: 8) {
                Image(systemName: "hand.tap.fill").foregroundStyle(.tint)
                Text(sel.shortDayLabel).font(.subheadline.weight(.semibold))
                Button("Clear") { withAnimation { store.selected = nil } }.buttonStyle(.bordered).controlSize(.small)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(.regularMaterial, in: Capsule())
            .shadow(radius: 4, y: 1)
        }
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
        let hasStatus = store.errorMessage != nil || !store.warnings.isEmpty
        let statusH: CGFloat = hasStatus ? 34 : -gap   // no status row: its gap disappears too
        @ViewBuilder func card(_ c: Card, _ h: CGFloat) -> some View {
            if c.bp {
                BloodPressureCard(days: days, range: store.range, window: store.window, selected: $store.selected,
                                  guideline: store.bpGuideline, emptyNote: bpNote)
                    .frame(height: h)
            } else if c.bpMap {
                BloodPressureMapCard(days: days, readings: store.bpReadings, window: store.window, selected: $store.selected,
                                     guideline: store.bpGuideline, emptyNote: bpNote)
                    .frame(height: h)
            } else if c.bodyComp {
                BodyCompositionCard(days: days, range: store.range, window: store.window,
                                    selected: $store.selected, trendDays: store.effectiveRollingDays)
                    .frame(height: h)
            } else {
            ChartCard(title: c.title, icon: c.icon, series: c.series, days: days,
                      range: store.range, window: store.window,
                      selected: $store.selected, yIncludesZero: c.zero, emptyNote: c.note,
                      goal: c.goal, zones: c.zones,
                      yDomain: c.domain, footnote: c.footnote,
                      showDate: c.nightDetail,
                      extra: (c.nightDetail && store.selected != nil) ? AnyView(NightDetailView(date: store.selected!, height: screen == .sleep ? 150 : 112)) : nil,
                      dashedGrid: c.dashedGrid, majorGrid: c.majorGrid, stages: c.stages)
                .frame(height: h)
            }
        }
        return ScrollView {
            VStack(spacing: gap) {
                if hasStatus { statusBar.frame(minHeight: statusH) }
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
                        // two columns: heart rate stays low so blood pressure gets the room; sleep and the map share the right
                        let colH = avail - gap
                        HStack(alignment: .top, spacing: gap) {
                            VStack(spacing: gap) { card(cs[0], colH * 0.36); card(cs[2], colH * 0.64) }
                            VStack(spacing: gap) { card(cs[1], colH * 0.5); card(cs[3], colH * 0.5) }
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
        var bodyComp = false; var bp = false; var bpMap = false; var domain: ClosedRange<Double>? = nil
        var dashedGrid: [Double] = []; var majorGrid: Double? = nil
    }

    private var bpNote: String {
        store.useHealthKit ? "No blood pressure readings in Apple Health for this period."
                           : "Garmin's Personal API has no blood pressure data. Connect Apple Health in Settings."
    }

    /// Resting heart rate axis starts at 45 bpm (it only goes lower if the data does), top rounded up to the next 5.
    private var rhrDomain: ClosedRange<Double>? {
        let v = store.visible.flatMap { [$0[.rhr], $0[.rhrAvg]] }.compactMap { $0 }
        guard let mn = v.min(), let mx = v.max() else { return nil }
        let lo = min(45, (mn / 5).rounded(.down) * 5)
        let hi = max(lo + 10, ((mx + 1) / 5).rounded(.up) * 5)
        return lo...hi
    }

    /// Thin dashed lines on every odd bpm value (47, 49, 51 …); the fat marker line is at 50.
    private var rhrOddLines: [Double] {
        guard let d = rhrDomain else { return [] }
        return stride(from: Int(d.lowerBound.rounded(.up)), through: Int(d.upperBound.rounded(.down)), by: 1).filter { $0 % 2 != 0 }.map(Double.init)
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
            Card(title: "Resting heart rate", icon: "heart.fill", series: rhrSeries, domain: rhrDomain, dashedGrid: rhrOddLines, majorGrid: 50),
            sleepStageCard,
            Card(title: "Blood pressure", icon: "waveform.path.ecg", series: [], bp: true),
            Card(title: "Blood pressure map", icon: "scope", series: [], bpMap: true),
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
            Card(title: "Resting heart rate", icon: "heart.fill", series: rhrSeries, domain: rhrDomain, dashedGrid: rhrOddLines, majorGrid: 50),
            stressCard,
        ]
        }
    }
}
