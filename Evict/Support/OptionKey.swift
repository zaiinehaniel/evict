import AppKit
import Observation

/// Whether ⌥ is held while the popover is open, so "Move to Trash" can turn into "Delete".
@MainActor
@Observable
final class OptionKey {
    static let shared = OptionKey()

    private(set) var isDown = false

    @ObservationIgnored private var monitor: Any?

    private init() {}

    /// Starts following ⌥, beginning with whether it's held right now.
    func start() {
        isDown = NSEvent.modifierFlags.contains(.option)
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            let isDown = event.modifierFlags.contains(.option)
            MainActor.assumeIsolated { self?.isDown = isDown }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isDown = false
    }
}
