import AppKit

/// A user-facing app (one that shows in the Dock) as Evict sees it.
struct RunningAppInfo: Identifiable {
    let id: pid_t
    let bundleIdentifier: String?
    let bundleURL: URL?
    let launchDate: Date?
    let name: String
    let icon: NSImage

    init(_ app: NSRunningApplication) {
        id = app.processIdentifier
        bundleIdentifier = app.bundleIdentifier
        bundleURL = app.bundleURL
        launchDate = app.launchDate
        // Some apps (e.g. WhatsApp) ship invisible bidi marks in their name.
        let rawName = app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "Unknown"
        name = rawName.trimmingCharacters(in: .controlCharacters.union(.whitespaces))
        icon = app.icon ?? NSWorkspace.shared.icon(for: .application)
    }

    #if DEBUG
    /// Sample data for README screenshots.
    init(demoID: pid_t, name: String, bundleIdentifier: String) {
        id = demoID
        self.bundleIdentifier = bundleIdentifier
        bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier)
        launchDate = nil
        self.name = name
        icon = bundleURL.map { NSWorkspace.shared.icon(forFile: $0.path) } ?? NSWorkspace.shared.icon(for: .application)
    }
    #endif

    /// Identity that survives relaunches; used for protection and per-app rules.
    var key: String? { bundleIdentifier ?? bundleURL?.path }
}
