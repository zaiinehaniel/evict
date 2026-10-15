import AppKit
import SwiftUI

/// The Settings window: General, Rules and About, as toolbar tabs.
///
/// Built with AppKit rather than SwiftUI's `Settings` scene, which can't be
/// opened reliably from a menu bar–only app.
@MainActor
final class SettingsWindowController: NSWindowController {
    init(settings: AppSettings, monitor: AppMonitor) {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.tab(String(localized: "General"), symbol: "gearshape",
                                     GeneralSettingsView(settings: settings)))
        tabs.addTabViewItem(Self.tab(String(localized: "Rules"), symbol: "clock.badge.checkmark",
                                     RulesSettingsView(settings: settings, monitor: monitor)))
        tabs.addTabViewItem(Self.tab(String(localized: "About"), symbol: "info.circle",
                                     AboutView()))

        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate()
        if window?.isVisible == false { window?.center() }
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    #if DEBUG
    var selectedTab: Int {
        get { (contentViewController as? NSTabViewController)?.selectedTabViewItemIndex ?? 0 }
        set { (contentViewController as? NSTabViewController)?.selectedTabViewItemIndex = newValue }
    }
    #endif

    private static func tab(_ title: String, symbol: String, _ view: some View) -> NSTabViewItem {
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]
        hosting.title = title // the window title follows the selected tab
        let item = NSTabViewItem(viewController: hosting)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}
