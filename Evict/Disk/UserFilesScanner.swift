import Foundation

enum UserFilesScanner {
    private static let staleDownload: TimeInterval = 86_400 * 90
    private static let staleProject: TimeInterval = 86_400 * 60
    private static let largeFile: UInt64 = 1 << 30
    private static let installerWords = ["install", "setup", "macos", "-mac", "darwin", "universal", "arm64", "x64"]

    private static var home: URL { DiskRoots.home }

    /// One walk of the home folder producing every Your files category except `.trash`, with precedence applied.
    static func scan(denied: Set<ProtectedFolder>) async -> [DiskCategoryID: [DiskItem]] {
        walk(denied: denied)
    }

    /// Synchronous: `FileManager`'s enumerator can't be iterated from an async context.
    private static func walk(denied: Set<ProtectedFolder>) -> [DiskCategoryID: [DiskItem]] {
        let downloads = ProtectedFolder.downloads.url.path
        let desktop = ProtectedFolder.desktop.url.path
        var found: [DiskCategoryID: [DiskItem]] = [:]

        guard let enumerator = FileManager.default.enumerator(
            at: home, includingPropertiesForKeys: HomeExclusions.resourceKeys, options: [.skipsPackageDescendants]
        ) else { return [:] }

        let keys = Set(HomeExclusions.resourceKeys)
        let deniedPaths = Set(denied.map { $0.url.standardizedFileURL.path })
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited % 500 == 0, Task.isCancelled { return [:] }
            let values = try? url.resourceValues(forKeys: keys)
            guard let values else { continue }
            let isDirectory = values.isDirectory == true
            if HomeExclusions.shouldSkip(url, values, deniedPaths: deniedPaths) {
                if isDirectory { enumerator.skipDescendants() }
                continue
            }
            let parent = url.deletingLastPathComponent().path

            if isDirectory {
                if url.lastPathComponent == DiskRoots.nodeModules {
                    enumerator.skipDescendants()
                    if let item = staleNodeModules(url) { found[.nodeModules, default: []].append(item) }
                } else if parent == downloads, isOlderThan(staleDownload, FileSizes.newestModification(in: url)) {
                    found[.oldDownloads, default: []].append(item(url, isDirectory: true))
                }
                continue
            }

            let topLevelOfDownloadsOrDesktop = parent == downloads || parent == desktop
            if topLevelOfDownloadsOrDesktop, isInstaller(url) {
                found[.installers, default: []].append(item(url, isDirectory: false, size: size(values)))
            }
            if parent == downloads, isOlderThan(staleDownload, FileSizes.lastUsed(url)) {
                found[.oldDownloads, default: []].append(item(url, isDirectory: false, size: size(values)))
            }
            if size(values) > largeFile {
                found[.largeFiles, default: []].append(
                    item(url, isDirectory: false, size: size(values), detail: relative(url.deletingLastPathComponent())))
            }
        }
        if Task.isCancelled { return [:] }

        found[.xcodeArchives] = xcodeArchives()
        return resolvePrecedence(found)
    }

    /// The Trash's entries, or nil when it can't be listed (no Full Disk Access).
    static func scanTrash() async -> DiskCategory? {
        let trash = DiskRoots.trash
        guard let entries = try? FileManager.default.contentsOfDirectory(at: trash, includingPropertiesForKeys: nil) else {
            return nil
        }
        var items: [DiskItem] = []
        for url in entries {
            if Task.isCancelled { return nil }
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            items.append(item(url, isDirectory: isDirectory, size: FileSizes.allocatedSize(of: url)))
        }
        items.sort { $0.size > $1.size }
        return DiskCategory(id: .trash, items: items, total: items.reduce(0) { $0 + $1.size })
    }

    // MARK: Rules

    private static func isInstaller(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if ["dmg", "pkg", "iso"].contains(ext) { return true }
        let name = url.lastPathComponent.lowercased()
        return ext == "zip" && installerWords.contains { name.contains($0) }
    }

    /// `~/Library/Developer/Xcode/Archives/*/*.xcarchive` older than 90 days. The one Library path read here.
    private static func xcodeArchives() -> [DiskItem] {
        let root = DiskRoots.archives
        let fileManager = FileManager.default
        let days = (try? fileManager.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        var items: [DiskItem] = []
        for day in days {
            let archives = (try? fileManager.contentsOfDirectory(at: day, includingPropertiesForKeys: nil)) ?? []
            for archive in archives where archive.pathExtension == DiskRoots.archiveExtension {
                if Task.isCancelled { return [] }
                guard let created = try? archive.resourceValues(forKeys: [.creationDateKey]).creationDate,
                      isOlderThan(staleDownload, created) else { continue }
                items.append(item(archive, isDirectory: true, detail: created.formatted(date: .abbreviated, time: .omitted)))
            }
        }
        return items
    }

    /// A `node_modules` whose project hasn't been touched in 60 days, judged by the newest entry beside it.
    private static func staleNodeModules(_ modules: URL) -> DiskItem? {
        let project = modules.deletingLastPathComponent()
        let siblings = (try? FileManager.default.contentsOfDirectory(
            at: project, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        let dates = siblings.filter { $0.lastPathComponent != DiskRoots.nodeModules }
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
        let newest = dates.max() ?? (try? project.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        guard isOlderThan(staleProject, newest) else { return nil }
        let size = FileSizes.allocatedSize(of: modules)
        guard size > 0 else { return nil }
        return DiskItem(id: modules.path, name: project.lastPathComponent, detail: relative(project), path: modules.path,
                        isDirectory: true, size: size, lastUsed: newest)
    }

    /// The earlier category wins; an item inside an already-listed item's path is dropped.
    private static func resolvePrecedence(_ found: [DiskCategoryID: [DiskItem]]) -> [DiskCategoryID: [DiskItem]] {
        var listed: [String] = []
        var result: [DiskCategoryID: [DiskItem]] = [:]
        for id in DiskCategoryID.allCases where id.group == .yourFiles && id != .trash {
            let kept = (found[id] ?? []).filter { item in
                !listed.contains { item.id == $0 || item.id.hasPrefix($0 + "/") }
            }
            listed += kept.map(\.id)
            result[id] = kept.sorted { $0.size > $1.size }
        }
        return result
    }

    // MARK: Helpers

    private static func isOlderThan(_ interval: TimeInterval, _ date: Date?) -> Bool {
        date.map { Date().timeIntervalSince($0) > interval } ?? false
    }

    private static func size(_ values: URLResourceValues) -> UInt64 {
        UInt64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
    }

    private static func item(_ url: URL, isDirectory: Bool, size: UInt64? = nil, detail: String? = nil) -> DiskItem {
        DiskItem(id: url.path, name: url.lastPathComponent, detail: detail, path: url.path, isDirectory: isDirectory,
                 size: size ?? FileSizes.allocatedSize(of: url), lastUsed: FileSizes.lastUsed(url))
    }

    /// "~/dev/app" shown as "dev/app".
    private static func relative(_ url: URL) -> String {
        let prefix = home.path + "/"
        return url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : url.path
    }
}
