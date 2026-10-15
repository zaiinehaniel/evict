import Foundation

/// An app Evict closed (by hand or automatically), kept so it can be reopened.
struct EvictedApp: Codable, Identifiable, Equatable {
    var id = UUID()
    let name: String
    let bundlePath: String?
    /// Memory the app held when it was closed.
    let freed: UInt64?
    var date: Date
    let automatic: Bool

    /// How many to keep, and for how long they're offered for reopening.
    static let limit = 10
    static let lifetime: TimeInterval = 24 * 3600

    init(_ entry: AppEntry, automatic: Bool) {
        name = entry.app.name
        bundlePath = entry.app.bundleURL?.path
        freed = entry.memory
        date = Date()
        self.automatic = automatic
    }

    #if DEBUG
    init(name: String, bundlePath: String?, freed: UInt64?, date: Date, automatic: Bool) {
        self.name = name
        self.bundlePath = bundlePath
        self.freed = freed
        self.date = date
        self.automatic = automatic
    }
    #endif

    static func pruned(_ items: [EvictedApp], now: Date = Date()) -> [EvictedApp] {
        Array(items.filter { now.timeIntervalSince($0.date) < lifetime }.prefix(limit))
    }
}
