import AppKit
import Observation

/// What the Disk tab shows: free space and the categories of reclaimable data.
///
/// Scanning only happens when asked (the tab being shown), off the main actor, and
/// each category lands as soon as it's done. The last result is cached so the tab
/// never opens empty.
@MainActor
@Observable
final class DiskMonitor {
    private(set) var volume: DiskVolume?
    /// Only the categories with something in them.
    private(set) var categories: [DiskCategoryID: DiskCategory] = [:]
    private(set) var isScanning = false
    /// Whether the user opted in to scanning Downloads, Desktop and Documents.
    private(set) var userFilesEnabled = Preferences.diskUserFilesEnabled
    /// The protected folders macOS refused access to on the last scan.
    private(set) var deniedFolders: [ProtectedFolder] = []
    private(set) var docker: DockerState = .notInstalled

    @ObservationIgnored private var scanTask: Task<Void, Never>?

    init() {
        volume = DiskVolume.current()
        categories = Dictionary(Preferences.diskScanCache.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Cancels any running scan, then scans every enabled category concurrently.
    func scan() {
        scanTask?.cancel()
        scanTask = Task { await runScan() }
    }

    /// Records the opt-in and scans. The scan checks each protected folder in order, and the
    /// first check of each is what makes macOS ask.
    func enableUserFiles() {
        Preferences.diskUserFilesEnabled = true
        userFilesEnabled = true
        scan()
    }

    /// Prunes Docker's unused images and build cache, starting Docker first if it's stopped
    /// and quitting it again only if this call started it.
    func cleanDocker() async {
        if case .working = docker { return }
        docker = .working(.cleaning)
        var startedByUs = false
        do {
            if try await Docker.status() == .stopped {
                docker = .working(.starting)
                startedByUs = try await Docker.start()
                docker = .working(.cleaning)
            }
            try await Docker.prune()
            if startedByUs {
                docker = .working(.stopping)
                await Docker.quit()
            }
            categories[.docker] = nil
            Preferences.diskScanCache = DiskCategoryID.allCases.compactMap { categories[$0] }
            docker = .cleaned
        } catch {
            // A failed start has already quit what it launched.
            if startedByUs { await Docker.quit() }
            docker = .failed(error.localizedDescription)
        }
    }

    func cancelScan() {
        scanTask?.cancel()
        scanTask = nil
        isScanning = false
    }

    func category(_ id: DiskCategoryID) -> DiskCategory? {
        categories[id]
    }

    /// What one click can reclaim: all of the group's categories, or every one for `nil`.
    func reclaimable(_ group: DiskGroup?) -> UInt64 {
        DiskCategoryID.allCases
            .filter { group == nil || $0.group == group }
            .reduce(0) { $0 + selection(in: $1).reduce(0) { $0 + $1.size } }
    }

    /// The items a category's one-click action would remove: everything but running apps' caches.
    func selection(in id: DiskCategoryID) -> [DiskItem] {
        (categories[id]?.items ?? []).filter { !$0.isOpen }
    }

    #if DEBUG
    /// `scan()`, awaited — for `--dump-disk`.
    func scanAndWait() async {
        scan()
        await scanTask?.value
    }
    #endif

    private func runScan() async {
        isScanning = true
        volume = DiskVolume.current()
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let ids = DiskCategoryID.allCases.filter { $0.group == .appJunk && $0 != .docker }
        let enabled = userFilesEnabled
        if !enabled { clearUserFiles() }
        var scanDocker = true
        if case .working = docker { scanDocker = false }
        await withTaskGroup(of: Void.self) { group in
            if scanDocker {
                group.addTask { await self.scanDocker() }
            }
            for id in ids {
                group.addTask {
                    let items = await AppJunkScanner.scan(id, runningBundleIDs: running)
                    await self.store(items, in: id)
                }
            }
            // Before the opt-in nothing touches Your files, protected folders included.
            guard enabled else { return }
            group.addTask {
                // Each check may sit behind a macOS prompt, so it must not hold up App junk.
                var denied: [ProtectedFolder] = []
                for folder in ProtectedFolder.allCases {
                    if Task.isCancelled { return }
                    if !folder.hasAccess() { denied.append(folder) }
                }
                await self.setDenied(denied)
                let found = await UserFilesScanner.scan(denied: Set(denied))
                guard !Task.isCancelled else { return }
                for id in DiskCategoryID.allCases where id.group == .yourFiles && id != .trash {
                    await self.store(found[id] ?? [], in: id)
                }
            }
            group.addTask {
                let trash = await UserFilesScanner.scanTrash()
                await self.store(trash?.items ?? [], in: .trash)
            }
        }
        guard !Task.isCancelled else { return }
        isScanning = false
    }

    private func scanDocker() async {
        guard Docker.app != nil || Docker.cli != nil else {
            setDocker(.notInstalled, items: [])
            return
        }
        do {
            switch try await Docker.status() {
            case .running:
                setDocker(.running, items: try await Docker.usage())
            case .stopped:
                setDocker(.stopped(vmSize: FileSizes.allocatedSize(of: Docker.vmDisk)), items: [])
            }
        } catch is CancellationError {
        } catch {
            setDocker(.failed(error.localizedDescription), items: [])
        }
    }

    /// Records a scan's result, unless the scan was cancelled or a clean is under way.
    private func setDocker(_ state: DockerState, items: [DiskItem]) {
        guard !Task.isCancelled else { return }
        if case .working = docker { return }
        docker = state
        store(items, in: .docker)
    }

    private func setDenied(_ folders: [ProtectedFolder]) {
        guard !Task.isCancelled else { return }
        deniedFolders = folders
    }

    /// Drops Your files results (and the denied list) left from an earlier opted-in run.
    private func clearUserFiles() {
        deniedFolders = []
        for id in DiskCategoryID.allCases where id.group == .yourFiles { categories[id] = nil }
        Preferences.diskScanCache = DiskCategoryID.allCases.compactMap { categories[$0] }
    }

    private func store(_ items: [DiskItem], in id: DiskCategoryID) {
        guard !Task.isCancelled else { return }
        let items = items.sorted { $0.size > $1.size }
        if items.isEmpty {
            categories[id] = nil
        } else {
            categories[id] = DiskCategory(id: id, items: items, total: items.reduce(0) { $0 + $1.size })
        }
        Preferences.diskScanCache = DiskCategoryID.allCases.compactMap { categories[$0] }
    }
}
