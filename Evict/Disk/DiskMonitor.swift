import AppKit
import Observation

/// A one-click removal waiting for the user to confirm it inline in the popover.
enum DiskConfirmation: Equatable {
    case category(DiskCategoryID, permanently: Bool)
    case clearAppJunk
}

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
    /// Ids of the items the user unchecked. Listed and counted, but left out of every one-click action.
    private(set) var kept = Set(Preferences.keptDiskItems)
    /// Cleared by the popover on close.
    var pendingConfirmation: DiskConfirmation?
    /// Categories with a removal under way; their rows show a spinner.
    private(set) var working: Set<DiskCategoryID> = []
    /// How many items each category's last removal couldn't remove. Cleared on the next scan.
    private(set) var failures: [DiskCategoryID: Int] = [:]

    @ObservationIgnored private var scanTask: Task<Void, Never>?
    /// Items removed since the running scan started, so its late results can't bring them back.
    @ObservationIgnored private var removedDuringScan: Set<String> = []
    private static let removalConcurrency = 4

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

    /// What "Clear app junk" would remove: the one-click selection of every App junk category but Docker.
    var clearableAppJunk: UInt64 {
        Self.bulkAppJunk.reduce(0) { $0 + selection(in: $1).reduce(0) { $0 + $1.size } }
    }

    /// What one click can reclaim: all of the group's categories, or every one for `nil`.
    func reclaimable(_ group: DiskGroup?) -> UInt64 {
        DiskCategoryID.allCases
            .filter { group == nil || $0.group == group }
            .reduce(0) { $0 + selection(in: $1).reduce(0) { $0 + $1.size } }
    }

    /// The items a category's one-click action would remove: everything but kept items and running apps' caches.
    func selection(in id: DiskCategoryID) -> [DiskItem] {
        (categories[id]?.items ?? []).filter { !$0.isOpen && !kept.contains($0.id) }
    }

    func setKept(_ kept: Bool, _ item: DiskItem) {
        setKept(kept, [item])
    }

    /// Keeps or un-keeps several items with one write, for "Select all".
    func setKept(_ kept: Bool, _ items: [DiskItem]) {
        let ids = Set(items.map(\.id))
        let updated = kept ? self.kept.union(ids) : self.kept.subtracting(ids)
        guard updated != self.kept else { return }
        self.kept = updated
        Preferences.keptDiskItems = updated.sorted()
    }

    /// Removes `items` from category `id`: moved to the Trash, deleted, or (for the Trash) emptied,
    /// as the category says. `permanently` deletes what would otherwise go to the Trash.
    func remove(_ items: [DiskItem], from id: DiskCategoryID, permanently: Bool) async {
        pendingConfirmation = nil
        await remove([id: items], permanently: permanently)
    }

    /// Removes the one-click selection of every App junk category. Docker has its own clean.
    func clearAppJunk() async {
        pendingConfirmation = nil
        await remove(Dictionary(uniqueKeysWithValues: Self.bulkAppJunk.map { ($0, selection(in: $0)) }), permanently: false)
    }

    /// The categories "Clear app junk" covers. Docker has its own clean, since it may have to start Docker.
    private static let bulkAppJunk = DiskCategoryID.allCases.filter { $0.group == .appJunk && $0 != .docker }

    #if DEBUG
    /// Sample data for the README screenshots. Touches neither the disk nor the saved preferences.
    init(demoCategories: [(DiskCategoryID, [DiskItem])], dockerVMSize: UInt64, volume: DiskVolume, userFilesEnabled: Bool) {
        self.volume = volume
        self.userFilesEnabled = userFilesEnabled
        self.kept = []
        self.docker = .stopped(vmSize: dockerVMSize)
        for (id, items) in demoCategories {
            categories[id] = DiskCategory(id: id, items: items, total: items.reduce(0) { $0 + $1.size })
        }
    }

    /// `scan()`, awaited — for `--dump-disk`.
    func scanAndWait() async {
        scan()
        await scanTask?.value
    }
    #endif

    private func runScan() async {
        // Cancelled before it got to run: `cancelScan()` has already cleared `isScanning`, keep it that way.
        guard !Task.isCancelled else { return }
        isScanning = true
        failures = [:]
        removedDuringScan = []
        volume = DiskVolume.current()
        let listedBefore = categories.mapValues { Set($0.items.map(\.id)) }
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let ids = DiskCategoryID.allCases.filter { $0.group == .appJunk && $0 != .docker }
        let enabled = userFilesEnabled
        if !enabled { clearUserFiles() }
        var scanDocker = true
        if case .working = docker { scanDocker = false }
        // Each task returns the categories it scanned in full.
        let scanned = await withTaskGroup(of: [DiskCategoryID].self) { group in
            if scanDocker {
                group.addTask { await self.scanDocker() ? [.docker] : [] }
            }
            for id in ids {
                group.addTask {
                    let items = await AppJunkScanner.scan(id, runningBundleIDs: running)
                    await self.store(items, in: id)
                    return [id]
                }
            }
            // Before the opt-in nothing touches Your files, protected folders included.
            if enabled {
                group.addTask {
                    // Each check may sit behind a macOS prompt, so it must not hold up App junk.
                    var denied: [ProtectedFolder] = []
                    for folder in ProtectedFolder.allCases {
                        if Task.isCancelled { return [] }
                        if !folder.hasAccess() { denied.append(folder) }
                    }
                    await self.setDenied(denied)
                    let found = await UserFilesScanner.scan(denied: Set(denied))
                    guard !Task.isCancelled else { return [] }
                    let walked = DiskCategoryID.allCases.filter { $0.group == .yourFiles && $0 != .trash }
                    for id in walked {
                        await self.store(found[id] ?? [], in: id)
                    }
                    // A denied folder wasn't looked at, so what was in it may still be there.
                    return denied.isEmpty ? walked : []
                }
                group.addTask {
                    let trash = await UserFilesScanner.scanTrash()
                    await self.store(trash?.items ?? [], in: .trash)
                    return trash == nil ? [] : [.trash]
                }
            }
            var scanned: Set<DiskCategoryID> = []
            for await ids in group { scanned.formUnion(ids) }
            return scanned
        }
        guard !Task.isCancelled else { return }
        pruneKept(listedBefore: listedBefore, scanned: scanned)
        isScanning = false
    }

    /// Forgets the kept ids that are gone: listed nowhere now, and listed before only by categories
    /// this scan covered in full. An id no category listed before is forgotten only after a scan of everything.
    private func pruneKept(listedBefore: [DiskCategoryID: Set<String>], scanned: Set<DiskCategoryID>) {
        let listed = Set(categories.values.flatMap { $0.items.map(\.id) })
        let scannedEverything = scanned == Set(DiskCategoryID.allCases)
        let gone = kept.filter { id in
            guard !listed.contains(id) else { return false }
            let owners = listedBefore.filter { $0.value.contains(id) }.keys
            return owners.isEmpty ? scannedEverything : owners.allSatisfy(scanned.contains)
        }
        guard !gone.isEmpty else { return }
        kept.subtract(gone)
        Preferences.keptDiskItems = kept.sorted()
    }

    /// Whether Docker's items were listed in full (it's running, or not installed at all).
    private func scanDocker() async -> Bool {
        guard Docker.app != nil || Docker.cli != nil else {
            return setDocker(.notInstalled, items: [])
        }
        do {
            switch try await Docker.status() {
            case .running:
                return setDocker(.running, items: try await Docker.usage())
            case .stopped:
                setDocker(.stopped(vmSize: FileSizes.allocatedSize(of: Docker.vmDisk)), items: [])
                return false
            }
        } catch is CancellationError {
            return false
        } catch {
            setDocker(.failed(error.localizedDescription), items: [])
            return false
        }
    }

    /// Records a scan's result, unless the scan was cancelled or a clean is under way. False if it didn't.
    @discardableResult
    private func setDocker(_ state: DockerState, items: [DiskItem]) -> Bool {
        guard !Task.isCancelled else { return false }
        if case .working = docker { return false }
        docker = state
        store(items, in: .docker)
        return true
    }

    /// Removes each category's items, at most four at a time across all of them. Only items the
    /// category still lists are removed. Items already gone from the disk leave the list quietly.
    private func remove(_ batches: [DiskCategoryID: [DiskItem]], permanently: Bool) async {
        let batches = batches.filter { id, items in
            id.removal != .docker && !working.contains(id) && !items.isEmpty
        }
        guard !batches.isEmpty else { return }
        working.formUnion(batches.keys)

        var queue: [(id: DiskCategoryID, item: DiskItem)] = []
        for (id, items) in batches {
            // The scan's own copy, once per id: never a path the scan didn't list in this category.
            // One it no longer lists was already dealt with.
            let listed = Dictionary((categories[id]?.items ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for itemID in Set(items.map(\.id)) {
                if let item = listed[itemID] { queue.append((id, item)) }
            }
        }

        var failed: [DiskCategoryID: Int] = [:]
        var removed: [DiskCategoryID: Set<String>] = [:]
        await withTaskGroup(of: (id: DiskCategoryID, itemID: String, outcome: DiskRemover.Outcome).self) { group in
            var pending = queue[...]
            func add(_ next: (id: DiskCategoryID, item: DiskItem)) {
                group.addTask {
                    let outcome = await DiskRemover.remove(next.item, from: next.id, permanently: permanently)
                    return (next.id, next.item.id, outcome)
                }
            }
            for _ in 0..<Self.removalConcurrency {
                guard let next = pending.popFirst() else { break }
                add(next)
            }
            for await result in group {
                switch result.outcome {
                case .removed, .gone: removed[result.id, default: []].insert(result.itemID)
                case .failed: failed[result.id, default: 0] += 1
                }
                if let next = pending.popFirst() { add(next) }
            }
        }

        for (id, gone) in removed {
            guard let category = categories[id] else { continue }
            put(category.items.filter { !gone.contains($0.id) }, in: id)
        }
        let gone = removed.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        removedDuringScan.formUnion(gone)
        if !kept.isDisjoint(with: gone) {
            kept.subtract(gone)
            Preferences.keptDiskItems = kept.sorted()
        }
        for id in batches.keys { failures[id] = failed[id] }
        Preferences.diskScanCache = DiskCategoryID.allCases.compactMap { categories[$0] }
        volume = DiskVolume.current()
        working.subtract(batches.keys)
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
        // A scan that started before a removal may still list what it removed.
        put(items.filter { !removedDuringScan.contains($0.id) }, in: id)
        Preferences.diskScanCache = DiskCategoryID.allCases.compactMap { categories[$0] }
    }

    private func put(_ items: [DiskItem], in id: DiskCategoryID) {
        let items = items.sorted { $0.size > $1.size }
        if items.isEmpty {
            categories[id] = nil
        } else {
            categories[id] = DiskCategory(id: id, items: items, total: items.reduce(0) { $0 + $1.size })
        }
    }
}
