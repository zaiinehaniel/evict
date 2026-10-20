import Foundation

/// Internal state persisted between launches (user-facing settings live in `AppSettings`).
enum Preferences {
    private static var defaults: UserDefaults { .standard }

    private enum Key {
        static let lastUsedByProcess = "lastUsedByProcess"
        static let recentlyEvicted = "recentlyEvicted"
        static let diskScanCache = "diskScanCache"
    }

    /// Last-used timestamps keyed by "pid@launchTime", so idle time survives
    /// relaunching Evict as long as the app itself keeps running.
    static var lastUsedByProcess: [String: Double] {
        get { defaults.dictionary(forKey: Key.lastUsedByProcess) as? [String: Double] ?? [:] }
        set { defaults.set(newValue, forKey: Key.lastUsedByProcess) }
    }

    /// Apps Evict closed recently, newest first.
    static var recentlyEvicted: [EvictedApp] {
        get {
            guard let data = defaults.data(forKey: Key.recentlyEvicted) else { return [] }
            return (try? JSONDecoder().decode([EvictedApp].self, from: data)) ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.recentlyEvicted) }
    }

    /// The last disk scan, so the Disk tab never opens empty.
    static var diskScanCache: [DiskCategory] {
        get {
            guard let data = defaults.data(forKey: Key.diskScanCache) else { return [] }
            return (try? JSONDecoder().decode([DiskCategory].self, from: data)) ?? []
        }
        set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Key.diskScanCache) }
    }
}
