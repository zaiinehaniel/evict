import Foundation

/// One row in the popover: an app plus everything Evict knows about it right now.
struct AppEntry: Identifiable {
    let app: RunningAppInfo
    /// Footprint of the app and all its helper processes. `nil` until first sampled.
    let memory: UInt64?
    /// Time since the user last used the app. Always 0 for the active app.
    let idle: TimeInterval
    /// This app's idle time limit (its own rule, or the default; halved on battery
    /// when the user asked for that).
    let idleLimit: TimeInterval
    let isActive: Bool
    let isProtected: Bool
    /// Doing something that must not be interrupted, even if it looks idle.
    let busyReason: BusyReason?
    /// Asked to quit and still shutting down.
    let isQuitting: Bool
    /// Time until automatic eviction, when it's on and applies to this app.
    let evictsIn: TimeInterval?
    /// CPU it keeps using while idle, as a share of one core — what it costs in battery.
    let backgroundCPU: Double?

    var id: pid_t { app.id }
    /// Past its idle limit (never true for the active app).
    var isIdle: Bool { !isActive && idle >= idleLimit }
    var isEvictable: Bool { isIdle && !isProtected && busyReason == nil && !isQuitting }

    /// Idle CPU worth mentioning (busy apps are already labeled as working).
    var notableBackgroundCPU: Double? {
        guard !isActive, busyReason == nil, let cpu = backgroundCPU, cpu >= 0.02 else { return nil }
        return cpu
    }
}

enum SortOrder: String, CaseIterable, Identifiable {
    case worthClosing, memory, idleTime, name

    var id: Self { self }

    var title: LocalizedStringResource {
        switch self {
        case .worthClosing: "Worth closing"
        case .memory: "Memory"
        case .idleTime: "Idle time"
        case .name: "Name"
        }
    }

    func sorted(_ entries: [AppEntry]) -> [AppEntry] {
        entries.sorted { a, b in
            switch self {
            case .worthClosing:
                let (sa, sb) = (Self.closeScore(a), Self.closeScore(b))
                if sa != sb { return sa > sb }
            case .memory:
                let (ma, mb) = (a.memory ?? 0, b.memory ?? 0)
                if ma != mb { return ma > mb }
            case .idleTime:
                if a.idle != b.idle { return a.idle > b.idle }
            case .name:
                break
            }
            return a.app.name.localizedStandardCompare(b.app.name) == .orderedAscending
        }
    }

    /// Lots of memory held for a long time ranks first; apps Evict won't close sink.
    private static func closeScore(_ entry: AppEntry) -> Double {
        if entry.isActive || entry.isProtected || entry.busyReason != nil || entry.isQuitting { return -1 }
        // Apps burning CPU in the background are worth more to close.
        let energy = 1 + 5 * (entry.notableBackgroundCPU ?? 0)
        return Double(entry.memory ?? 0) * max(entry.idle, 60) * energy
    }
}
