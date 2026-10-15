import AppKit
import UserNotifications

/// Closes apps past their idle limit on its own, when the user turned that on.
/// Each eviction is announced a minute ahead with a "Keep Open" notification,
/// and every app still gets a graceful quit (⌘Q), never a force quit.
@MainActor
final class AutoEvictor: NSObject, UNUserNotificationCenterDelegate {
    private let monitor: AppMonitor
    private var settings: AppSettings { monitor.settings }
    private var loop: Task<Void, Never>?
    private var requestedAuthorization = false
    /// Last automatic attempt per app, so an app that doesn't quit (say, it's
    /// asking to save) isn't asked again every few seconds.
    private var lastAttempt: [pid_t: Date] = [:]

    private static let gracePeriod: TimeInterval = 60
    private static let retryAfter: TimeInterval = 15 * 60
    private static let categoryID = "eviction"
    nonisolated private static let keepOpenActionID = "keep-open"

    init(monitor: AppMonitor) {
        self.monitor = monitor
        super.init()

        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let keepOpen = UNNotificationAction(identifier: Self.keepOpenActionID, title: String(localized: "Keep Open"))
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryID, actions: [keepOpen], intentIdentifiers: []),
        ])

        loop = Task { [weak self] in
            while !Task.isCancelled {
                let hasPending = self?.tick() ?? false
                // Check more often while an announced eviction is counting down.
                try? await Task.sleep(for: hasPending ? .seconds(10) : .seconds(30))
            }
        }
    }

    // MARK: - Loop

    /// Returns whether evictions are pending.
    private func tick() -> Bool {
        guard settings.autoEvict else {
            monitor.pendingEvictions.keys.forEach(cancel)
            return false
        }
        requestAuthorizationIfNeeded()
        monitor.sample()

        let now = monitor.now
        let candidates = monitor.isAutoEvicting ? monitor.entries.filter(\.isEvictable) : []
        let candidateIDs = Set(candidates.map(\.id))

        // Anything that stopped qualifying (used again, busy, protected…) is spared.
        for pid in monitor.pendingEvictions.keys where !candidateIDs.contains(pid) {
            cancel(pid)
        }

        for entry in candidates {
            if let last = lastAttempt[entry.id], now.timeIntervalSince(last) < Self.retryAfter { continue }
            if let deadline = monitor.pendingEvictions[entry.id] {
                if now >= deadline { evict(entry) }
            } else if settings.notifyBeforeEvicting {
                monitor.pendingEvictions[entry.id] = now.addingTimeInterval(Self.gracePeriod)
                announce(entry)
            } else {
                evict(entry)
            }
        }
        return !monitor.pendingEvictions.isEmpty
    }

    private func evict(_ entry: AppEntry) {
        cancel(entry.id)
        lastAttempt[entry.id] = Date()
        monitor.requestQuit(entry, automatic: true)
    }

    private func cancel(_ pid: pid_t) {
        monitor.pendingEvictions[pid] = nil
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: [Self.notificationID(pid)])
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationID(pid)])
    }

    private func keepOpen(_ pid: pid_t) {
        cancel(pid)
        monitor.markUsed(pid)
    }

    // MARK: - Notifications

    private func requestAuthorizationIfNeeded() {
        guard settings.notifyBeforeEvicting, !requestedAuthorization else { return }
        requestedAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func announce(_ entry: AppEntry) {
        let content = UNMutableNotificationContent()
        if let memory = entry.memory {
            content.title = String(localized: "Evicting \(entry.app.name) in 1 min — \(Format.memory(memory))")
        } else {
            content.title = String(localized: "Evicting \(entry.app.name) in 1 min")
        }
        content.body = String(localized: "Idle for \(Format.duration(entry.idle)). Choose Keep Open to leave it running.")
        content.categoryIdentifier = Self.categoryID
        content.threadIdentifier = Self.categoryID
        content.userInfo = ["pid": Int(entry.id)]

        let request = UNNotificationRequest(identifier: Self.notificationID(entry.id), content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    private static func notificationID(_ pid: pid_t) -> String { "evict.\(pid)" }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == Self.keepOpenActionID,
              let pid = response.notification.request.content.userInfo["pid"] as? Int else { return }
        await keepOpen(pid_t(pid))
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
