#if DEBUG
import AppKit
import SwiftUI

/// Renders the popover with sample data to PNGs, for the README:
///   Evict.app/Contents/MacOS/Evict --render-screenshots <dir>
@MainActor
enum ScreenshotRenderer {
    static var outputDirectory: URL? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--render-screenshots"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1], isDirectory: true)
    }

    static func render(to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, appearance) in [("popover-light", NSAppearance.Name.aqua), ("popover-dark", .darkAqua)] {
            let view = PopoverView(monitor: demoMonitor(), diskMonitor: DiskMonitor())
                .background(Color(nsColor: .windowBackgroundColor))
                // Not the user's defaults, so the Memory tab is drawn whichever tab they last used.
                .defaultAppStorage(screenshotDefaults)
                .environment(\.controlActiveState, .key)
            let hosting = NSHostingView(rootView: view)
            hosting.appearance = NSAppearance(named: appearance)
            hosting.setFrameSize(hosting.fittingSize)

            // Key + active so controls draw with the accent color, parked off-screen.
            let window = KeyWindow(contentRect: hosting.bounds, styleMask: .borderless, backing: .buffered, defer: false)
            window.appearance = NSAppearance(named: appearance)
            window.contentView = hosting
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))

            let scale: CGFloat = 2
            guard let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(hosting.bounds.width * scale), pixelsHigh: Int(hosting.bounds.height * scale),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0
            ) else { continue }
            rep.size = hosting.bounds.size
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            window.orderOut(nil)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent("\(name).png"))
        }
        renderSettings(to: directory)
    }

    /// The Settings window, title bar and toolbar included, one PNG per tab.
    static func renderSettings(to directory: URL) {
        let monitor = demoMonitor()
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let controller = SettingsWindowController(settings: monitor.settings, monitor: monitor)
            guard let window = controller.window else { continue }
            window.appearance = NSAppearance(named: appearance)
            for (index, tab) in ["general", "rules", "about"].enumerated() {
                controller.selectedTab = index
                window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
                window.orderFrontRegardless()
                RunLoop.main.run(until: Date().addingTimeInterval(0.6))
                guard let frameView = window.contentView?.superview else { continue }
                let bounds = frameView.bounds
                guard let rep = NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * 2), pixelsHigh: Int(bounds.height * 2),
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                    bytesPerRow: 0, bitsPerPixel: 0
                ) else { continue }
                rep.size = bounds.size
                frameView.cacheDisplay(in: bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: directory.appendingPathComponent("settings-\(tab)-\(name).png"))
            }
            window.orderOut(nil)
        }
    }

    /// Never written to: the views only read their defaults here.
    private static let screenshotDefaults = UserDefaults(suiteName: "com.hanielcortes.evict.screenshots") ?? .standard

    private final class KeyWindow: NSWindow {
        override var canBecomeKey: Bool { true }
    }

    private static func demoMonitor() -> AppMonitor {
        let gb: Double = 1_073_741_824
        func app(_ id: pid_t, _ name: String, _ bundleID: String, _ memoryGB: Double, idleMinutes: Double) -> (app: RunningAppInfo, memory: UInt64, idle: TimeInterval) {
            (RunningAppInfo(demoID: id, name: name, bundleIdentifier: bundleID), UInt64(memoryGB * gb), idleMinutes * 60)
        }
        let apps = [
            app(1, "Google Chrome", "com.google.Chrome", 3.4, idleMinutes: 0),
            app(2, "Xcode", "com.apple.dt.Xcode", 2.6, idleMinutes: 370),
            app(3, "Visual Studio Code", "com.microsoft.VSCode", 1.9, idleMinutes: 302),
            app(4, "Notes", "com.apple.Notes", 0.32, idleMinutes: 190),
            app(5, "Postman", "com.postmanlabs.mac", 0.62, idleMinutes: 252),
            app(6, "Spotify", "com.spotify.client", 0.41, idleMinutes: 420),
            app(7, "Safari", "com.apple.Safari", 0.86, idleMinutes: 52),
            app(8, "Messages", "com.apple.MobileSMS", 0.14, idleMinutes: 48),
            app(9, "Mail", "com.apple.mail", 0.21, idleMinutes: 22),
        ]
        let settings = AppSettings(store: nil)
        settings.autoEvict = true
        settings.setRule(.never, for: apps[5].app)
        settings.setRule(.minutes(30), for: apps[4].app)
        settings.setRule(.minutes(240), for: apps[1].app)
        return AppMonitor(
            settings: settings,
            demoApps: apps,
            activePID: 1,
            busy: [6: .playingAudio],
            backgroundCPU: [3: 0.06],
            recentlyEvicted: [
                EvictedApp(name: "Photos", bundlePath: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Photos")?.path,
                           freed: UInt64(1.3 * gb), date: Date().addingTimeInterval(-14 * 60), automatic: true),
            ],
            background: [
                BackgroundGroup(id: "docker", name: "Docker",
                                bundlePath: NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.docker.docker")?.path,
                                memory: UInt64(2.4 * gb), processCount: 11),
                BackgroundGroup(id: "node", name: "node", bundlePath: nil, memory: UInt64(0.38 * gb), processCount: 2),
            ],
            system: SystemMemory(used: UInt64(11.2 * gb), total: UInt64(16 * gb), pressure: .normal)
        )
    }
}
#endif
