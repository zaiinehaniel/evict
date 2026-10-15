import CoreAudio
import Foundation
import IOKit.pwr_mgt

/// Why an app that looks idle is actually doing something. Ordered by priority:
/// when several apply, the highest one is shown.
enum BusyReason: Int, Comparable, Sendable {
    case working, keepingAwake, keepingScreenOn, playingAudio, inCall

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var label: String {
        switch self {
        case .working: String(localized: "Working")
        case .keepingAwake: String(localized: "Keeping Mac awake")
        case .keepingScreenOn: String(localized: "Keeping screen on")
        case .playingAudio: String(localized: "Playing audio")
        case .inCall: String(localized: "In a call")
        }
    }
}

/// Finds apps Evict must never interrupt: playing audio, on a call, holding the
/// Mac awake (downloads, exports, video, `caffeinate`) or busy on the CPU.
enum BusyDetector {
    /// Share of one CPU core, averaged over a sampling window, above which an app
    /// counts as working on something (rendering, exporting, indexing…).
    static let cpuThreshold = 0.15

    static func reasons(for apps: Set<pid_t>, snapshot: ProcessSnapshot, cpuShare: [pid_t: Double]) -> [pid_t: BusyReason] {
        var result: [pid_t: BusyReason] = [:]
        func note(_ app: pid_t, _ reason: BusyReason) {
            result[app] = max(result[app] ?? reason, reason)
        }

        for (app, share) in cpuShare where share >= cpuThreshold && apps.contains(app) {
            note(app, .working)
        }
        for (pid, reason) in powerAssertions() {
            if let app = snapshot.owner(of: pid, among: apps) { note(app, reason) }
        }
        for (pid, activity) in audioActivity() {
            guard let app = snapshot.owner(of: pid, among: apps) else { continue }
            if activity.input { note(app, .inCall) } else if activity.output { note(app, .playingAudio) }
        }
        return result
    }

    // MARK: - Power assertions

    private static let systemSleepTypes: Set<String> = [
        "PreventUserIdleSystemSleep", "PreventSystemSleep", "NoIdleSleepAssertion",
    ]
    private static let displaySleepTypes: Set<String> = [
        "PreventUserIdleDisplaySleep", "NoDisplaySleepAssertion",
    ]

    /// Processes holding the Mac (or its display) awake. Assertions a daemon holds
    /// on an app's behalf are credited to the app.
    private static func powerAssertions() -> [pid_t: BusyReason] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return [:] }

        var result: [pid_t: BusyReason] = [:]
        for (pid, assertions) in byProcess {
            for assertion in assertions {
                guard let type = assertion["AssertType"] as? String else { continue }
                let reason: BusyReason
                if systemSleepTypes.contains(type) {
                    reason = .keepingAwake
                } else if displaySleepTypes.contains(type) {
                    reason = .keepingScreenOn
                } else {
                    continue
                }
                let owner = (assertion["AssertionOnBehalfOfPID"] as? NSNumber)?.int32Value ?? pid.int32Value
                result[owner] = max(result[owner] ?? reason, reason)
            }
        }
        return result
    }

    // MARK: - Audio

    /// Processes currently playing or recording audio (macOS 14.2+).
    private static func audioActivity() -> [pid_t: (output: Bool, input: Bool)] {
        guard #available(macOS 14.2, *) else { return [:] }

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let system = AudioObjectID(kAudioObjectSystemObject)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [:] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [:] }

        var result: [pid_t: (output: Bool, input: Bool)] = [:]
        for object in objects {
            let output: UInt32 = property(of: object, kAudioProcessPropertyIsRunningOutput) ?? 0
            let input: UInt32 = property(of: object, kAudioProcessPropertyIsRunningInput) ?? 0
            guard output != 0 || input != 0, let pid: pid_t = property(of: object, kAudioProcessPropertyPID) else { continue }
            result[pid] = (output != 0, input != 0)
        }
        return result
    }

    private static func property<T>(of object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> T? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(MemoryLayout<T>.size)
        let value = UnsafeMutablePointer<T>.allocate(capacity: 1)
        defer { value.deallocate() }
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else { return nil }
        return value.pointee
    }
}
