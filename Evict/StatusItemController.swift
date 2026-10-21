import AppKit
import SwiftUI

/// Owns the menu bar icon, the popover it opens and the Settings window.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let monitor: AppMonitor
    private let diskMonitor: DiskMonitor
    private var outsideClickMonitor: Any?
    private var menuBarTask: Task<Void, Never>?
    private lazy var settingsWindow = SettingsWindowController(settings: monitor.settings, monitor: monitor)

    init(monitor: AppMonitor, diskMonitor: DiskMonitor) {
        self.monitor = monitor
        self.diskMonitor = diskMonitor
        super.init()

        let content = PopoverView(monitor: monitor, diskMonitor: diskMonitor, openSettings: { [weak self] in self?.openSettings() })
        let hosting = NSHostingController(rootView: content)
        hosting.sizingOptions = [.preferredContentSize]
        popover.contentViewController = hosting
        popover.behavior = .transient
        popover.delegate = self

        if let button = statusItem.button {
            let image = NSImage(resource: .menuBarIcon)
            image.size = NSSize(width: 18, height: 18)
            image.isTemplate = true
            image.accessibilityDescription = "Evict"
            button.image = image
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        startMenuBarUpdates()
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func openSettings() {
        popover.performClose(nil)
        settingsWindow.show()
    }

    // MARK: - Memory % in the menu bar

    /// Keeps the optional "62%" next to the icon current. Reading whole-Mac memory
    /// is a single cheap kernel call, so a few seconds' cadence costs nothing.
    private func startMenuBarUpdates() {
        menuBarTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateMenuBarTitle()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private func updateMenuBarTitle() {
        guard let button = statusItem.button else { return }
        guard monitor.settings.showMemoryInMenuBar else {
            if !button.title.isEmpty { button.title = "" }
            return
        }
        let percent = Int((SystemMemory.current().fraction * 100).rounded())
        button.attributedTitle = NSAttributedString(
            string: " \(percent)%",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)]
        )
        button.setAccessibilityValue(String(localized: "\(percent)% of memory used"))
    }

    // MARK: - NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) {
        monitor.setLive(true)
        OptionKey.shared.start()
        // The popover's content stays in place between openings, so it can't start this itself.
        if PopoverTab.current == .disk { diskMonitor.scan() }
        // `.transient` alone misses clicks in other apps when macOS declines to
        // activate us, so close on any click outside Evict as well.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.popover.performClose(nil) }
        }
    }

    func popoverDidClose(_ notification: Notification) {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        outsideClickMonitor = nil
        monitor.setLive(false)
        diskMonitor.cancelScan()
        diskMonitor.pendingConfirmation = nil
        OptionKey.shared.stop()
        updateMenuBarTitle()
        // Hand focus back to whatever the user was using (e.g. after Esc), unless
        // one of our windows (Settings) is now in front.
        let hasOpenWindow = NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
        if NSApp.isActive, !hasOpenWindow { NSApp.deactivate() }
    }
}
