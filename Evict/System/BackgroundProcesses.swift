import Darwin
import Foundation

/// Memory held outside the Dock: menu bar apps, helpers and agents (Docker's VM,
/// Creative Cloud, sync clients…), grouped by the app they come from.
/// Read-only — Evict never closes them.
struct BackgroundGroup: Identifiable, Sendable {
    /// The app bundle path, or the executable name for processes outside any app.
    let id: String
    let name: String
    let bundlePath: String?
    let memory: UInt64
    let processCount: Int
}

enum BackgroundProcesses {
    /// Groups smaller than this aren't worth a row.
    static let minimumMemory: UInt64 = 100 * 1_048_576

    /// macOS's own daemons and agents — part of the system, not something to explain.
    private static let systemPrefixes = [
        "/System/", "/usr/libexec/", "/usr/sbin/", "/usr/bin/", "/sbin/", "/bin/", "/Library/Apple/",
    ]

    /// Background groups, largest first. `apps` are the Dock apps (already listed);
    /// `ownBundlePath` excludes Evict itself.
    static func groups(in snapshot: ProcessSnapshot, excluding apps: Set<pid_t>, ownBundlePath: String) -> [BackgroundGroup] {
        var totals: [String: (name: String, bundlePath: String?, memory: UInt64, count: Int)] = [:]

        for (pid, process) in snapshot.processes where snapshot.owner(of: pid, among: apps) == nil {
            guard let source = sourcePath(of: pid, process: process) else { continue }

            let key: String
            let name: String
            let bundlePath: String?
            if let bundle = outermostBundle(in: source) {
                guard bundle != ownBundlePath else { continue }
                key = bundle
                bundlePath = bundle
                name = displayName(ofBundle: bundle)
            } else {
                name = (source as NSString).lastPathComponent
                key = name
                bundlePath = nil
            }
            totals[key, default: (name, bundlePath, 0, 0)].memory += process.footprint
            totals[key, default: (name, bundlePath, 0, 0)].count += 1
        }

        return totals
            .map { BackgroundGroup(id: $0.key, name: $0.value.name, bundlePath: $0.value.bundlePath,
                                   memory: $0.value.memory, processCount: $0.value.count) }
            .filter { $0.memory >= minimumMemory }
            .sorted { $0.memory > $1.memory }
    }

    /// Where a process "comes from": the app responsible for it (so an XPC service
    /// counts toward the app that launched it), else its own executable. `nil` for
    /// macOS's own processes.
    private static func sourcePath(of pid: pid_t, process: ProcessSnapshot.Process) -> String? {
        if let responsible = process.responsible, responsible != pid,
           let path = executablePath(of: responsible), !isSystem(path) {
            return path
        }
        guard let path = executablePath(of: pid), !isSystem(path) else { return nil }
        return path
    }

    private static func isSystem(_ path: String) -> Bool {
        systemPrefixes.contains { path.hasPrefix($0) }
    }

    /// "/Applications/Docker.app/Contents/MacOS/com.docker.backend" → "/Applications/Docker.app".
    /// Nested helpers resolve to the outer app, not "… Helper.app".
    private static func outermostBundle(in path: String) -> String? {
        guard let range = path.range(of: ".app/") else { return path.hasSuffix(".app") ? path : nil }
        return String(path[..<range.lowerBound]) + ".app"
    }

    private static func displayName(ofBundle path: String) -> String {
        let name = FileManager.default.displayName(atPath: path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN)) // PROC_PIDPATHINFO_MAXSIZE
        let length = Int(proc_pidpath(pid, &buffer, UInt32(buffer.count)))
        guard length > 0 else { return nil }
        return String(decoding: buffer[..<length].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
