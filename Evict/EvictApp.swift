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
            NSApp.terminate(nil)
        }
    }
    #endif
}
