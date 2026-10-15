import Darwin
import Dispatch

/// One pass over every process we can read: how much memory and CPU each uses,
/// and which app it belongs to.
///
/// Memory uses the same metric as Activity Monitor's "Memory" column
/// (`phys_footprint`). A process belongs to an app when the app is "responsible"
/// for it (how macOS attributes XPC services like Safari's WebContent) or when it
/// descends from the app (how Chrome, Slack and VS Code spawn their helpers).
struct ProcessSnapshot: Sendable {
    struct Process: Sendable {
        let footprint: UInt64
        /// User + system CPU time, in nanoseconds.
        let cpuTime: UInt64
        let parent: pid_t
        let responsible: pid_t?
    }

    struct AppUsage: Sendable {
        var footprint: UInt64 = 0
        var cpuTime: UInt64 = 0
    }

    let processes: [pid_t: Process]
    /// Monotonic time the snapshot was taken, in nanoseconds.
    let uptime: UInt64

    static func take() -> ProcessSnapshot {
        var processes: [pid_t: Process] = [:]
        for pid in allPIDs() {
            guard let usage = resourceUsage(of: pid) else { continue } // other users' processes
            processes[pid] = Process(
                footprint: usage.ri_phys_footprint,
                cpuTime: nanoseconds(fromMachTime: usage.ri_user_time + usage.ri_system_time),
                parent: parent(of: pid) ?? 0,
                responsible: responsiblePID?(pid)
            )
        }
        return ProcessSnapshot(processes: processes, uptime: DispatchTime.now().uptimeNanoseconds)
    }

    /// The app among `apps` that `pid` belongs to, if any.
    func owner(of pid: pid_t, among apps: Set<pid_t>) -> pid_t? {
        if apps.contains(pid) { return pid }
        if let responsible = processes[pid]?.responsible ?? Self.responsiblePID?(pid), apps.contains(responsible) {
            return responsible
        }

        var current = processes[pid]?.parent ?? 0
        for _ in 0..<16 where current > 1 {
            if apps.contains(current) { return current }
            guard let next = processes[current]?.parent else { return nil }
            current = next
        }
        return nil
    }

    /// Memory and CPU time per app, helpers included.
    func usage(for apps: Set<pid_t>) -> [pid_t: AppUsage] {
        var totals: [pid_t: AppUsage] = [:]
        for (pid, process) in processes {
            guard let owner = owner(of: pid, among: apps) else { continue }
            totals[owner, default: AppUsage()].footprint += process.footprint
            totals[owner, default: AppUsage()].cpuTime += process.cpuTime
        }
        return totals
    }

    // MARK: - System calls

    private typealias ResponsiblePIDFunction = @convention(c) (pid_t) -> pid_t

    /// Private but stable libsystem call that Activity Monitor relies on. Optional:
    /// without it we fall back to the process tree only.
    private static let responsiblePID: ResponsiblePIDFunction? = {
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(rtldDefault, "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: ResponsiblePIDFunction.self)
    }()

    /// `ri_user_time` / `ri_system_time` are in Mach time units (not ns on Apple Silicon).
    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    private static func nanoseconds(fromMachTime time: UInt64) -> UInt64 {
        guard timebase.denom > 0 else { return time }
        return time / UInt64(timebase.denom) * UInt64(timebase.numer)
    }

    private static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        return pids.prefix(Int(max(count, 0))).filter { $0 > 0 }
    }

    private static func resourceUsage(of pid: pid_t) -> rusage_info_v4? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        return result == 0 ? info : nil
    }

    private static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }
}
