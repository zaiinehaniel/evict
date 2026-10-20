import Foundation

/// Where each category's items live. The scanners look only here, and `DiskRemover` removes
/// nothing anywhere else, so a stale cache or a scanner mistake can't reach the rest of the disk.
enum DiskRoots {
    static let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    static let library = home.appending(path: "Library")
    static let xcode = library.appending(path: "Developer/Xcode")
    static let derivedData = xcode.appending(path: "DerivedData")
    /// `~/Library/Developer/Xcode/<platform> DeviceSupport/<version>`.
    static let deviceSupportSuffix = "DeviceSupport"
    /// `~/Library/Developer/Xcode/Archives/<date>/<name>.xcarchive`.
    static let archives = xcode.appending(path: "Archives")
    static let archiveExtension = "xcarchive"
    static let simulatorDevices = library.appending(path: "Developer/CoreSimulator/Devices")
    static let caches = library.appending(path: "Caches")
    /// The system's own caches, never listed.
    static let appleCachePrefix = "com.apple."
    static let nodeModules = "node_modules"
    static let trash = home.appending(path: ".Trash")

    /// Package-manager caches. Also skipped by the app caches scan.
    static let packageCaches: [(name: String, url: URL)] = [
        ("Homebrew", "Library/Caches/Homebrew"),
        ("npm", ".npm/_cacache"),
        ("pip", "Library/Caches/pip"),
        ("Yarn", "Library/Caches/Yarn"),
        ("pnpm", "Library/pnpm/store"),
        ("CocoaPods", "Library/Caches/CocoaPods"),
        ("Gradle", ".gradle/caches"),
        ("SwiftPM", "Library/Caches/org.swift.swiftpm"),
    ].map { (name: $0.0, url: home.appending(path: $0.1)) }

    /// Whether `path` (absolute, with no "." or ".." components) is somewhere the scan of `id` lists items.
    static func contains(_ path: String, isDirectory: Bool, for id: DiskCategoryID) -> Bool {
        let parent = parentPath(path)
        let name = String(path.dropFirst(parent.count + 1))
        guard path.hasPrefix("/"), !name.isEmpty else { return false }
        let downloads = ProtectedFolder.downloads.url.standardizedFileURL.path
        let desktop = ProtectedFolder.desktop.url.standardizedFileURL.path

        switch id {
        case .xcodeBuildData:
            return parent == derivedData.path
        case .xcodeDeviceSupport:
            return parentPath(parent) == xcode.path && parent.hasSuffix(deviceSupportSuffix)
        case .packageCaches:
            return packageCaches.contains { $0.url.path == path }
        case .appCaches:
            return parent == caches.path && !name.hasPrefix(appleCachePrefix)
                && !packageCaches.contains { $0.url.path == path }
        case .xcodeArchives:
            return parentPath(parent) == archives.path && name.hasSuffix("." + archiveExtension)
        case .installers:
            return !isDirectory && (parent == downloads || parent == desktop)
        case .oldDownloads:
            return parent == downloads
        case .largeFiles:
            return !isDirectory && isLooseInHome(path)
        case .nodeModules:
            return isDirectory && name == nodeModules && isLooseInHome(path)
        case .trash:
            return parent == trash.path
        case .simulators, .docker:
            // Removed through their CLIs, never by path.
            return false
        }
    }

    /// What the home walk can list: below a top-level home folder (never one itself), outside
    /// `~/Library`, and inside no hidden folder.
    private static func isLooseInHome(_ path: String) -> Bool {
        guard path.hasPrefix(home.path + "/") else { return false }
        let components = path.dropFirst(home.path.count + 1).split(separator: "/")
        return components.count >= 2 && components.first != "Library" && !components.contains { $0.hasPrefix(".") }
    }

    /// Everything before the last "/" ("" for "/x").
    private static func parentPath(_ path: String) -> String {
        guard let slash = path.lastIndex(of: "/") else { return "" }
        return String(path[..<slash])
    }
}
