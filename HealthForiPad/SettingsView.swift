import SwiftUI

struct SettingsView: View {
    @Environment(DashboardStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var key = ""
    @State private var status: String?
    @State private var busy = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    SecureField(store.hasKey ? "•••••••• (saved in Keychain)" : "Paste personal API key", text: $key)
                        .textContentType(.password).autocorrectionDisabled().textInputAutocapitalization(.never)
                    Button("Verify & save") { Task { await save() } }.disabled(key.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                    if store.hasKey { Button("Remove saved key", role: .destructive) { Keychain.delete(); store.keyChanged(); status = "Key removed (cached data is kept)" } }
                    if let status { Text(status).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text("Garmin Connect personal API key") } footer: {
                    Text("Create one at connect.garmin.com → Settings → Personal API. It is stored only in this device's Keychain and sent only to personal.connectapi.garmin.com. Keys expire (30 d – 1 y); a 401 means you need a new one.")
                }
                Section {
                    Stepper(value: $store.sleepGoal, in: 5...10, step: 0.25) {
                        Text("Sleep goal: \(Field.sleepHours.format(store.sleepGoal))")
                    }
                    Picker("Trend lines (resting HR, weight)", selection: $store.rollingWindow) {
                        Text("Auto (by range)").tag(0)
                        ForEach([7, 14, 21, 28], id: \.self) { Text("\($0)-day average").tag($0) }
                    }
                } header: { Text("Goals & trends") } footer: {
                    Text("Auto uses a 7-day average for 1W/30D, 14 days for 90D and 28 days for 180D/1Y, so the line stays readable at every zoom level.")
                }
                Section {
                    Picker("Guideline", selection: $store.bpGuideline) {
                        ForEach(BPGuideline.allCases) { Text($0.label).tag($0) }
                    }
                } header: { Text("Blood pressure zones") } footer: {
                    Text("AHA: normal <120/80, elevated 120–129, stage 1 130–139/80–89, stage 2 ≥140/90.\nESC: optimal/normal <130/85, high-normal 130–139/85–89, grade 1 140–159/90–99, grade 2–3 ≥160/100. Zones are an orientation, not medical advice.")
                }
                Section {
                    Toggle("Read blood pressure from Apple Health", isOn: Binding(
                        get: { store.useHealthKit },
                        set: { on in
                            if on { Task { status = await store.enableHealthKit() } }
                            else { store.disableHealthKit() }
                        }))
                } header: { Text("Apple Health") } footer: {
                    Text("Garmin's Personal API has no blood pressure data. If your cuff syncs to Apple Health, readings are shown here. Read-only; stays on this device.")
                }
                Section {
                    LabeledContent("Cached", value: store.cacheSummary)
                    LabeledContent("Activity data", value: store.activitySummary).font(.caption)
                    Picker("Keep history back", selection: $store.historyYears) {
                        Text("1 year").tag(1); Text("2 years").tag(2); Text("3 years").tag(3); Text("5 years").tag(5); Text("10 years").tag(10); Text("Everything Garmin has").tag(99)
                    }
                    if let p = store.backfillProgress {
                        if store.historyYears >= 99 {
                            ProgressView { Text("Downloading history… back to \(store.coveredStartLabel)").font(.footnote) }
                        } else {
                            ProgressView(value: p) { Text("Downloading history… \(Int(p * 100)) %").font(.footnote) }
                        }
                    }
                    if store.isBackfilling {
                        Button("Stop download", role: .cancel) { store.cancelBackfill() }
                    } else {
                        Button("Download history now") { store.startBackfill() }
                            .disabled(!store.hasKey || store.useDemo)
                    }
                    if let m = store.backfillMessage { Text(m).font(.footnote).foregroundStyle(.secondary) }
                    Toggle("Download history automatically", isOn: $store.autoBackfill)
                    Toggle("Refresh latest data in background", isOn: $store.autoRefresh)
                    Button("Clear cache", role: .destructive) { store.clearCache() }
                } header: { Text("Data & history") } footer: {
                    Text("Garmin data is cached on this iPad, so the app opens instantly and only fetches new or missing days. “2 years” or more adds a 2Y range to the dashboard. Automatic download continues while the app is open and, when iOS allows, in the background (usually while idle, on Wi-Fi or charging; timing is up to iOS). Every step is saved, so interrupted downloads resume. Blood pressure from Apple Health is never cached.")
                }
                Section("Demo") {
                    Toggle("Use demo data", isOn: Binding(get: { store.useDemo }, set: { store.useDemo = $0; store.switchedDemo(); Task { await store.load() } }))
                }
                Section("Diagnostics — raw API responses") {
                    if store.rawSamples.isEmpty { Text("Load data first").foregroundStyle(.secondary) }
                    ForEach(store.rawSamples.keys.sorted(), id: \.self) { k in
                        NavigationLink(k) {
                            ScrollView { Text(store.rawSamples[k] ?? "").font(.system(.footnote, design: .monospaced)).textSelection(.enabled).padding() }
                                .navigationTitle(k)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .onDisappear { Task { if !store.useDemo { await store.load() } } }
    }

    private func save() async {
        busy = true; defer { busy = false }
        let k = key.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await GarminClient(apiKey: k).verify()
            Keychain.save(k)
            if store.useDemo { store.useDemo = false; store.switchedDemo() }
            store.keyChanged()
            key = ""; status = "Key accepted ✓"
            await store.load(manual: true)
            dismiss()
        } catch { status = "Failed: \(error.localizedDescription)" }
    }
}
