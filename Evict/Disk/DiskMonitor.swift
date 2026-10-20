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
        // Docker arrives with the Docker scanner, Your files with theirs.
        let ids = DiskCategoryID.allCases.filter { $0.group == .appJunk && $0 != .docker }
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask {
                    let items = await AppJunkScanner.scan(id, runningBundleIDs: running)
                    await self.store(items, in: id)
                }
            }
        }
        guard !Task.isCancelled else { return }
        isScanning = false
    }

    private func store(_ items: [DiskItem], in id: DiskCategoryID) {
        guard !Task.isCancelled else { return }
        if items.isEmpty {
            categories[id] = nil
        } else {
            categories[id] = DiskCategory(id: id, items: items, total: items.reduce(0) { $0 + $1.size })
        }
        Preferences.diskScanCache = DiskCategoryID.allCases.compactMap { categories[$0] }
    }
}
