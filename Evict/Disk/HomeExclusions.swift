import Foundation

/// The "Never scanned" rules: nothing from Drive, iCloud or the OS.
enum HomeExclusions {
    private static let cloudPrefixes = ["Dropbox", "Google Drive", "OneDrive", "Box", "iCloud Drive"]

    static let resourceKeys: [URLResourceKey] = [
        .isHiddenKey, .isPackageKey, .isSymbolicLinkKey, .isUbiquitousItemKey, .isDirectoryKey,
        .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey, .creationDateKey,
    ]

    private static let homeURL = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    private static let homePath = homeURL.path
    private static let libraryPath = homeURL.appending(path: "Library").path

    /// Whether the walker leaves `url` (and everything under it) alone. `denied` folders are skipped too.
    static func shouldSkip(_ url: URL, _ values: URLResourceValues, denied: Set<ProtectedFolder>) -> Bool {
        shouldSkip(url, values, deniedPaths: Set(denied.map { $0.url.standardizedFileURL.path }))
    }

    /// Same, with the denied folders' standardized paths worked out once by the caller.
    static func shouldSkip(_ url: URL, _ values: URLResourceValues, deniedPaths: Set<String>) -> Bool {
        let path = url.standardizedFileURL.path
        if isCloudOrOutsideHome(path: path, isUbiquitous: values.isUbiquitousItem) || path == libraryPath { return true }
        if values.isHidden == true || values.isPackage == true || values.isSymbolicLink == true { return true }
        return deniedPaths.contains(path)
    }

    /// Outside the home folder, or synced by iCloud, Dropbox, Google Drive, OneDrive or Box.
    /// Unlike `shouldSkip`, this lets the rest of `~/Library` through.
    static func isCloudOrOutsideHome(_ url: URL) -> Bool {
        let ubiquitous = try? url.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem
        return isCloudOrOutsideHome(path: url.standardizedFileURL.path, isUbiquitous: ubiquitous)
    }

    /// The single definition behind both entry points.
    private static func isCloudOrOutsideHome(path: String, isUbiquitous: Bool?) -> Bool {
        if isUbiquitous == true { return true }
        guard path.hasPrefix(homePath + "/") else { return true }
        let relative = path.dropFirst(homePath.count + 1)
        guard let first = relative.split(separator: "/").first else { return false }
        if cloudPrefixes.contains(where: { first.hasPrefix($0) }) { return true }
        return relative.hasPrefix("Library/Mobile Documents") || relative.hasPrefix("Library/CloudStorage")
    }
}
