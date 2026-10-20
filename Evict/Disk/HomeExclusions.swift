import Foundation

/// The "Never scanned" rules: nothing from Drive, iCloud or the OS.
enum HomeExclusions {
    private static let cloudPrefixes = ["Dropbox", "Google Drive", "OneDrive", "Box", "iCloud Drive"]

    static let resourceKeys: [URLResourceKey] = [
        .isHiddenKey, .isPackageKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .isDirectoryKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey, .creationDateKey,
    ]

    /// Whether the walker leaves `url` (and everything under it) alone. `denied` folders are skipped too.
    static func shouldSkip(_ url: URL, _ values: URLResourceValues, denied: Set<ProtectedFolder>) -> Bool {
        if isOutsideHomeOrCloudSynced(url) || values.isUbiquitousItem == true { return true }
        if url.standardizedFileURL.path == home.appending(path: "Library").path { return true }
        if values.isHidden == true || values.isPackage == true || values.isSymbolicLink == true { return true }
        return denied.contains { $0.url.path == url.standardizedFileURL.path }
    }

    /// Outside the home folder, or synced by iCloud, Dropbox, Google Drive, OneDrive or Box.
    /// Unlike `shouldSkip`, this lets the rest of `~/Library` through.
    static func isCloudOrOutsideHome(_ url: URL) -> Bool {
        isOutsideHomeOrCloudSynced(url) || (try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) == true
    }

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL }

    private static func isOutsideHomeOrCloudSynced(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let homePath = home.path
        guard path.hasPrefix(homePath + "/") else { return true }
        let relative = path.dropFirst(homePath.count + 1)
        guard let first = relative.split(separator: "/").first else { return false }
        if cloudPrefixes.contains(where: { first.hasPrefix($0) }) { return true }
        return relative.hasPrefix("Library/Mobile Documents") || relative.hasPrefix("Library/CloudStorage")
    }
}
