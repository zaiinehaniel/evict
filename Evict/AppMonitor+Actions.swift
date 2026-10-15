import AppKit

/// A quit waiting for the user to confirm it inline in the popover.
enum PendingConfirmation: Equatable {
    case quit(pid_t)
    case forceQuit(pid_t)
    case evictIdle
}

extension AppMonitor {
    /// Graceful quit, same as ⌘Q: the app can still ask to save unsaved work.
    func quit(_ entry: AppEntry) {
        pendingConfirmation = nil
        requestQuit(entry)
    }

    func forceQuit(_ entry: AppEntry) {
        pendingConfirmation = nil
        requestQuit(entry, force: true)
    }

    /// Quits every app past its idle limit that isn't protected, busy or in front.
    func evictIdleApps() {
        pendingConfirmation = nil
        for entry in entries where entry.isEvictable {
            requestQuit(entry)
        }
    }

    func toggleProtection(_ entry: AppEntry) {
        settings.setProtected(!entry.isProtected, for: entry.app)
    }

    func showInFinder(_ entry: AppEntry) {
        guard let url = entry.app.bundleURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
