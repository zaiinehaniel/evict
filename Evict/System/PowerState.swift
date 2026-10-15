import Foundation
import IOKit.ps

/// Whether the Mac is running on battery or in Low Power Mode — when idle apps
/// cost battery life, not just memory.
struct PowerState: Equatable, Sendable {
    var onBattery: Bool
    var lowPowerMode: Bool

    var isSavingEnergy: Bool { onBattery || lowPowerMode }

    static func current() -> PowerState {
        var onBattery = false
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let source = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            onBattery = (source as String) == kIOPSBatteryPowerValue
        }
        return PowerState(onBattery: onBattery, lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled)
    }
}
