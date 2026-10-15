import AppKit

/// An app identified by its key (bundle ID, or path for apps without one),
/// whether or not it's running — used by the Rules list.
struct AppReference: Identifiable {
    let key: String
    let name: String
    let icon: NSImage
    let url: URL?

    var id: String { key }

    init(key: String) {
        self.key = key
        url = key.hasPrefix("/")
            ? URL(fileURLWithPath: key)
            : NSWorkspace.shared.urlForApplication(withBundleIdentifier: key)
        if let url {
            let displayName = FileManager.default.displayName(atPath: url.path)
            name = displayName.hasSuffix(".app") ? String(displayName.dropLast(4)) : displayName
            icon = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            name = key
            icon = NSWorkspace.shared.icon(for: .application)
        }
    }

    /// The key Evict uses for the app bundle at `url`.
    static func key(for url: URL) -> String {
        Bundle(url: url)?.bundleIdentifier ?? url.path
    }
}
