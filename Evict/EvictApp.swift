import SwiftUI

@main
struct EvictApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Placeholder until the Settings window lands (step 5).
        Settings { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?
    private var autoEvictor: AutoEvictor?
    /// Passed to `StatusItemController` once the Disk tab exists.
    let diskMonitor = DiskMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let directory = ScreenshotRenderer.outputDirectory {
            ScreenshotRenderer.render(to: directory)
            NSApp.terminate(nil)
            return
        }
        if CommandLine.arguments.contains("--dump-state") {
            dumpState()
            return
        }
        if CommandLine.arguments.contains("--dump-disk") {
            dumpDisk()
            return
        }
        #endif
        let monitor = AppMonitor(settings: AppSettings())
        statusItemController = StatusItemController(monitor: monitor)
        autoEvictor = AutoEvictor(monitor: monitor)
    }

    #if DEBUG
    /// Prints what Evict sees (memory, idle, busy) after a full CPU window, then quits:
    ///   Evict.app/Contents/MacOS/Evict --dump-state
    private func dumpState() {
        let monitor = AppMonitor(settings: AppSettings())
        monitor.sample()
        Task {
            try? await Task.sleep(for: .seconds(21))
            monitor.sample()
            for entry in SortOrder.worthClosing.sorted(monitor.entries) {
                let memory = entry.memory.map(Format.memory) ?? "—"
                let busy = entry.busyReason.map { "\($0)" } ?? entry.backgroundCPU.map { String(format: "-  (cpu %.1f%%)", $0 * 100) } ?? "-"
                print("\(entry.app.name.padding(toLength: 24, withPad: " ", startingAt: 0)) \(memory.padding(toLength: 9, withPad: " ", startingAt: 0)) idle \(Format.duration(entry.idle).padding(toLength: 8, withPad: " ", startingAt: 0)) busy: \(busy)\(entry.isActive ? "  [active]" : "")\(entry.isProtected ? "  [protected]" : "")")
            }
            print("\nIn the background:")
            for group in monitor.background {
                print("  \(group.name.padding(toLength: 30, withPad: " ", startingAt: 0)) \(Format.memory(group.memory).padding(toLength: 9, withPad: " ", startingAt: 0)) \(group.processCount) processes  \(group.bundlePath ?? "")")
            }
            NSApp.terminate(nil)
        }
    }

    /// Prints what the Disk tab would show, then quits:
    ///   Evict.app/Contents/MacOS/Evict --dump-disk
    private func dumpDisk() {
        Task {
            let started = Date()
            await diskMonitor.scanAndWait()
            if let volume = diskMonitor.volume {
                print("Disk: \(Format.memory(volume.available)) free of \(Format.memory(volume.total))\(volume.isLow ? "  [low]" : "")")
            }
            for id in DiskCategoryID.allCases {
                guard let category = diskMonitor.category(id) else { continue }
                print("\n\(String(localized: id.title))  \(Format.memory(category.total))")
                for item in category.items.sorted(by: { $0.size > $1.size }) {
                    print("  \(item.name.padding(toLength: 30, withPad: " ", startingAt: 0)) \(Format.memory(item.size).padding(toLength: 9, withPad: " ", startingAt: 0)) \(item.detail ?? "")\(item.isOpen ? "  [open]" : "")")
                }
            }
            print("\nReclaimable: \(Format.memory(diskMonitor.reclaimable(nil)))  (scanned in \(String(format: "%.1f", Date().timeIntervalSince(started))) s)")
            NSApp.terminate(nil)
        }
    }
    #endif
}
