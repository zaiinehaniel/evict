import Foundation
import Observation

/// How long an app may sit idle before Evict closes it.
enum IdleRule: Hashable {
    case automatic          // the default idle time
    case minutes(Int)
    case never              // same as protected

    static let presets = [30, 60, 120, 240, 480]
}

/// User settings, persisted in UserDefaults. Pass `store: nil` for a throwaway
/// copy (README screenshots).
@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let store: UserDefaults?

    var defaultIdleMinutes: Int { didSet { store?.set(defaultIdleMinutes, forKey: Key.defaultIdleMinutes) } }
    var autoEvict: Bool { didSet { store?.set(autoEvict, forKey: Key.autoEvict) } }
    var notifyBeforeEvicting: Bool { didSet { store?.set(notifyBeforeEvicting, forKey: Key.notifyBeforeEvicting) } }
    var onlyUnderMemoryPressure: Bool { didSet { store?.set(onlyUnderMemoryPressure, forKey: Key.onlyUnderMemoryPressure) } }
    var showMemoryInMenuBar: Bool { didSet { store?.set(showMemoryInMenuBar, forKey: Key.showMemoryInMenuBar) } }
    /// On battery or in Low Power Mode, apps count as idle after half the time.
    var stricterOnBattery: Bool { didSet { store?.set(stricterOnBattery, forKey: Key.stricterOnBattery) } }
    /// App keys (bundle IDs) that Evict never touches.
    private(set) var protectedApps: Set<String> { didSet { store?.set(protectedApps.sorted(), forKey: Key.protectedApps) } }
    /// Per-app idle time in minutes, keyed by app key.
    private(set) var idleRules: [String: Int] { didSet { store?.set(idleRules, forKey: Key.idleRules) } }

    /// System apps Evict leaves alone no matter what.
    private static let alwaysProtected: Set<String> = ["com.apple.systempreferences"]

    private enum Key {
        static let defaultIdleMinutes = "defaultIdleMinutes"
        static let autoEvict = "autoEvict"
        static let notifyBeforeEvicting = "notifyBeforeEvicting"
        static let onlyUnderMemoryPressure = "onlyUnderMemoryPressure"
        static let showMemoryInMenuBar = "showMemoryInMenuBar"
        static let stricterOnBattery = "stricterOnBattery"
        static let protectedApps = "protectedApps"
        static let idleRules = "idleRules"
    }

    init(store: UserDefaults? = .standard) {
        self.store = store
        let minutes = store?.integer(forKey: Key.defaultIdleMinutes) ?? 0
        defaultIdleMinutes = minutes > 0 ? minutes : 60
        autoEvict = store?.object(forKey: Key.autoEvict) as? Bool ?? false
        notifyBeforeEvicting = store?.object(forKey: Key.notifyBeforeEvicting) as? Bool ?? true
        onlyUnderMemoryPressure = store?.object(forKey: Key.onlyUnderMemoryPressure) as? Bool ?? false
        showMemoryInMenuBar = store?.object(forKey: Key.showMemoryInMenuBar) as? Bool ?? false
        stricterOnBattery = store?.object(forKey: Key.stricterOnBattery) as? Bool ?? true
        protectedApps = Set(store?.stringArray(forKey: Key.protectedApps) ?? [])
        idleRules = store?.dictionary(forKey: Key.idleRules) as? [String: Int] ?? [:]
    }

    var defaultIdleLimit: TimeInterval { TimeInterval(defaultIdleMinutes) * 60 }

    func idleLimit(for app: RunningAppInfo) -> TimeInterval {
        app.key.flatMap { idleRules[$0] }.map { TimeInterval($0) * 60 } ?? defaultIdleLimit
    }

    func isProtected(_ app: RunningAppInfo) -> Bool {
        guard let key = app.key else { return false }
        return protectedApps.contains(key) || Self.alwaysProtected.contains(key)
    }

    func setProtected(_ isProtected: Bool, for app: RunningAppInfo) {
        guard let key = app.key else { return }
        if isProtected { protectedApps.insert(key) } else { protectedApps.remove(key) }
    }

    func rule(for app: RunningAppInfo) -> IdleRule {
        guard let key = app.key else { return .automatic }
        return Self.alwaysProtected.contains(key) ? .never : rule(forKey: key)
    }

    func setRule(_ rule: IdleRule, for app: RunningAppInfo) {
        guard let key = app.key else { return }
        setRule(rule, forKey: key)
    }

    // MARK: - Rules by app key

    /// Apps with their own rule (a custom idle time or "Never"), in a stable order.
    var ruledAppKeys: [String] {
        protectedApps.union(idleRules.keys).sorted()
    }

    func rule(forKey key: String) -> IdleRule {
        if protectedApps.contains(key) { return .never }
        return idleRules[key].map(IdleRule.minutes) ?? .automatic
    }

    func removeRule(forKey key: String) {
        setRule(.automatic, forKey: key)
    }

    func setRule(_ rule: IdleRule, forKey key: String) {
        switch rule {
        case .never:
            protectedApps.insert(key)
        case .minutes(let minutes):
            protectedApps.remove(key)
            idleRules[key] = minutes
        case .automatic:
            protectedApps.remove(key)
            idleRules[key] = nil
        }
    }
}
