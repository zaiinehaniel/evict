import AppKit
import Observation

/// Keeps a live picture of the apps the user opened: which one is in front, when
/// each was last used, how much memory it holds and whether it's busy.
///
/// App tracking is event-driven (launch, quit, activate). Processes are sampled
/// every few seconds while the popover is open, and by `AutoEvictor` otherwise.
@MainActor
@Observable
final class AppMonitor {
    let settings: AppSettings

    private(set) var apps: [RunningAppInfo] = []
    /// The app the user is actually using. Evict's own activation (opening the
    /// popover) is ignored so the previously frontmost app stays "Active".
    private(set) var activePID: pid_t?
    private(set) var memory: [pid_t: UInt64] = [:]
    private(set) var busy: [pid_t: BusyReason] = [:]
    private(set) var system = SystemMemory.current()
    private(set) var power = PowerState.current()
    private(set) var now = Date()
    /// Quits are confirmed inline in the popover; cleared when it closes.
    var pendingConfirmation: PendingConfirmation?
    /// Automatic evictions already announced, and when they'll happen.
    var pendingEvictions: [pid_t: Date] = [:]
    /// Apps Evict closed recently, newest first — offered for reopening.
    private(set) var recentlyEvicted: [EvictedApp] = []
    private var lastUsed: [pid_t: Date] = [:]

    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var liveTask: Task<Void, Never>?
    @ObservationIgnored private var isLive = false
    @ObservationIgnored private let ownPID = ProcessInfo.processInfo.processIdentifier
    @ObservationIgnored private let startedAt = Date()
    @ObservationIgnored private var cpuBaseline: (uptime: UInt64, cpuTime: [pid_t: UInt64])?
    private var cpuShare: [pid_t: Double] = [:]
    /// Quits Evict asked for, logged as evicted once the app actually terminates.
    @ObservationIgnored private var quitRequests: [pid_t: EvictedApp] = [:]

    /// Never listed: Evict itself is excluded by PID; Finder is always running.
    private static let excludedBundleIDs: Set<String> = ["com.apple.finder"]
    private static let sampleInterval: Duration = .seconds(3)
    /// CPU use is averaged over at least this long, so short spikes don't count as busy.
    private static let cpuWindow: UInt64 = 20_000_000_000

    init(settings: AppSettings) {
        self.settings = settings
        recentlyEvicted = EvictedApp.pruned(Preferences.recentlyEvicted)
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ownPID {
            activePID = front.processIdentifier
        }
        startObserving()
        refresh()
    }

    #if DEBUG
    /// A frozen monitor with sample data, for README screenshots. Observes nothing.
    init(settings: AppSettings, demoApps: [(app: RunningAppInfo, memory: UInt64, idle: TimeInterval)],
         activePID: pid_t?, busy: [pid_t: BusyReason], backgroundCPU: [pid_t: Double],
         recentlyEvicted: [EvictedApp], system: SystemMemory) {
        let now = Date()
        self.settings = settings
        self.now = now
        self.apps = demoApps.map(\.app)
        self.activePID = activePID
        self.busy = busy
        self.cpuShare = backgroundCPU
        self.recentlyEvicted = recentlyEvicted
        self.system = system
        for demo in demoApps {
            memory[demo.app.id] = demo.memory
            lastUsed[demo.app.id] = now.addingTimeInterval(-demo.idle)
        }
    }
    #endif

    // MARK: - Derived state

    /// Idle limits are halved right now (on battery, and the user asked for it).
    var isSavingEnergy: Bool { settings.stricterOnBattery && power.isSavingEnergy }

    /// Automatic eviction is on and its conditions hold right now.
    var isAutoEvicting: Bool {
        settings.autoEvict && (!settings.onlyUnderMemoryPressure || system.pressure != .normal)
    }

    var entries: [AppEntry] {
        let autoEvicting = isAutoEvicting
        let limitScale = isSavingEnergy ? 0.5 : 1
        return apps.map { app in
            let isActive = app.id == activePID
            let idle = isActive ? 0 : max(0, now.timeIntervalSince(lastUsed[app.id] ?? startedAt))
            let limit = settings.idleLimit(for: app) * limitScale
            let isProtected = settings.isProtected(app)
            let busyReason = busy[app.id]

            var evictsIn: TimeInterval?
            if autoEvicting, !isActive, !isProtected, busyReason == nil {
                evictsIn = pendingEvictions[app.id].map { max($0.timeIntervalSince(now), 0) } ?? max(limit - idle, 0)
            }

            return AppEntry(
                app: app,
                memory: memory[app.id],
                idle: idle,
                idleLimit: limit,
                isActive: isActive,
                isProtected: isProtected,
                busyReason: busyReason,
                evictsIn: evictsIn,
                backgroundCPU: cpuShare[app.id]
            )
        }
    }

    // MARK: - Live sampling

    /// Samples processes every few seconds while the popover is visible.
    func setLive(_ live: Bool) {
        isLive = live
        liveTask?.cancel()
        liveTask = nil
        guard live else {
            pendingConfirmation = nil
            return
        }

        sample()
        liveTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.sampleInterval)
                guard !Task.isCancelled else { return }
                self?.sample()
            }
        }
    }

    /// Measures memory, CPU and busy state of every app (~15 ms).
    func sample() {
        now = Date()
        system = SystemMemory.current()
        power = PowerState.current()
        let snapshot = ProcessSnapshot.take()
        // An app can vanish before its quit notification arrives (e.g. macOS
        // terminating a windowless app on its own); don't list a ghost.
        apps.removeAll { snapshot.processes[$0.id] == nil && kill($0.id, 0) != 0 }
        let appPIDs = Set(apps.map(\.id))
        let usage = snapshot.usage(for: appPIDs)
        memory = usage.mapValues(\.footprint)
        updateCPUShare(usage.mapValues(\.cpuTime), at: snapshot.uptime)
        busy = BusyDetector.reasons(for: appPIDs, snapshot: snapshot, cpuShare: cpuShare)
    }

    private func updateCPUShare(_ cpuTime: [pid_t: UInt64], at uptime: UInt64) {
        guard let baseline = cpuBaseline else {
            cpuBaseline = (uptime, cpuTime)
            return
        }
        let elapsed = uptime - baseline.uptime
        guard elapsed >= Self.cpuWindow else { return }
        cpuShare = [:]
        for (pid, time) in cpuTime {
            guard let before = baseline.cpuTime[pid], time >= before else { continue }
            cpuShare[pid] = Double(time - before) / Double(elapsed)
        }
        cpuBaseline = (uptime, cpuTime)
    }

    // MARK: - Quitting

    /// Asks the app to quit — gracefully (⌘Q) unless `force` — and remembers it
    /// so it shows up under "Recently evicted" once it's gone.
    func requestQuit(_ entry: AppEntry, force: Bool = false, automatic: Bool = false) {
        guard let app = NSRunningApplication(processIdentifier: entry.id) else { return }
        quitRequests[entry.id] = EvictedApp(entry, automatic: automatic)
        if force { app.forceTerminate() } else { app.terminate() }
    }

    func reopen(_ evicted: EvictedApp) {
        recentlyEvicted.removeAll { $0.id == evicted.id }
        Preferences.recentlyEvicted = recentlyEvicted
        guard let path = evicted.bundlePath else { return }
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: NSWorkspace.OpenConfiguration())
    }

    /// Treats the app as just used, e.g. after "Keep Open".
    func markUsed(_ pid: pid_t) {
        now = Date()
        lastUsed[pid] = now
        saveLastUsed()
    }

    // MARK: - Workspace events

    private func startObserving() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [Notification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
        ]
        observers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let activatedPID = note.name == NSWorkspace.didActivateApplicationNotification ? app?.processIdentifier : nil
                let terminatedPID = note.name == NSWorkspace.didTerminateApplicationNotification ? app?.processIdentifier : nil
                MainActor.assumeIsolated { self?.handle(activatedPID: activatedPID, terminatedPID: terminatedPID) }
            }
        }
    }

    private func handle(activatedPID: pid_t?, terminatedPID: pid_t?) {
        refresh()
        if let terminatedPID, var evicted = quitRequests.removeValue(forKey: terminatedPID) {
            evicted.date = Date()
            recentlyEvicted = EvictedApp.pruned([evicted] + recentlyEvicted)
            Preferences.recentlyEvicted = recentlyEvicted
        }
        guard let activatedPID, activatedPID != ownPID else { return }

        let now = Date()
        if let previous = activePID, previous != activatedPID {
            lastUsed[previous] = now // the user was using it until this moment
        }
        lastUsed[activatedPID] = now
        activePID = activatedPID
        saveLastUsed()
    }

    private func refresh() {
        apps = NSWorkspace.shared.runningApplications
            .filter { app in
                app.activationPolicy == .regular
                    && !app.isTerminated
                    && app.processIdentifier != ownPID
                    && !Self.excludedBundleIDs.contains(app.bundleIdentifier ?? "")
            }
            .map(RunningAppInfo.init)

        let running = Set(apps.map(\.id))
        lastUsed = lastUsed.filter { running.contains($0.key) }
        recentlyEvicted = EvictedApp.pruned(recentlyEvicted)

        // Apps we haven't seen yet: restore from a previous Evict session if the
        // process is the same, otherwise start counting from when we first saw it.
        let newApps = apps.filter { lastUsed[$0.id] == nil }
        if !newApps.isEmpty {
            let saved = Preferences.lastUsedByProcess
            for app in newApps {
                if let key = Self.processKey(app), let timestamp = saved[key] {
                    lastUsed[app.id] = Date(timeIntervalSince1970: timestamp)
                } else {
                    lastUsed[app.id] = max(app.launchDate ?? startedAt, startedAt)
                }
            }
        }

        if isLive { sample() }
    }

    private func saveLastUsed() {
        var saved: [String: Double] = [:]
        for app in apps {
            if let key = Self.processKey(app), let date = lastUsed[app.id] {
                saved[key] = date.timeIntervalSince1970
            }
        }
        Preferences.lastUsedByProcess = saved
    }

    private static func processKey(_ app: RunningAppInfo) -> String? {
        app.launchDate.map { "\(app.id)@\(Int($0.timeIntervalSince1970))" }
    }
}
