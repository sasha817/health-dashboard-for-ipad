import Foundation
import BackgroundTasks

/// Optional iOS background work. iOS decides when (and whether) it runs: typically while the iPad is idle,
/// on Wi-Fi / charging, and rarely more than a few times a day. Both jobs are resumable and save after each step.
enum BackgroundSync {
    static let refreshID = "app.healthdash.HealthForiPad.refresh"
    static let backfillID = "app.healthdash.HealthForiPad.backfill"

    static func register() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: refreshID, using: nil) { handle($0, backfill: false) }
        BGTaskScheduler.shared.register(forTaskWithIdentifier: backfillID, using: nil) { handle($0, backfill: true) }
    }

    @MainActor static func schedule() {
        let s = DashboardStore.shared
        let scheduler = BGTaskScheduler.shared
        scheduler.cancel(taskRequestWithIdentifier: refreshID)
        scheduler.cancel(taskRequestWithIdentifier: backfillID)
        if s.autoRefresh {
            let r = BGAppRefreshTaskRequest(identifier: refreshID)
            r.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 3600)
            try? scheduler.submit(r)
        }
        if s.autoBackfill {
            let r = BGProcessingTaskRequest(identifier: backfillID)
            r.requiresNetworkConnectivity = true
            r.requiresExternalPower = false
            r.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
            try? scheduler.submit(r)
        }
    }

    private static func handle(_ task: BGTask, backfill: Bool) {
        let work = Task { @MainActor in
            let s = DashboardStore.shared
            if backfill { await s.backfill(background: true) } else { await s.syncLatest() }
            schedule()
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        task.expirationHandler = { work.cancel() }
    }
}
