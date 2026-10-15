import Darwin
import Foundation

/// Whole-Mac memory, computed the way Activity Monitor's "Memory Used" is:
/// app memory + wired + compressed.
struct SystemMemory: Equatable, Sendable {
    enum Pressure: Sendable {
        case normal, warning, critical
    }

    var used: UInt64
    var total: UInt64
    var pressure: Pressure

    var fraction: Double { total > 0 ? min(Double(used) / Double(total), 1) : 0 }

    static func current() -> SystemMemory {
        SystemMemory(used: usedBytes(), total: ProcessInfo.processInfo.physicalMemory, pressure: currentPressure())
    }

    private static func usedBytes() -> UInt64 {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return 0 }

        let pageSize = UInt64(sysconf(_SC_PAGESIZE))
        let appPages = UInt64(stats.internal_page_count) - UInt64(min(stats.purgeable_count, stats.internal_page_count))
        let pages = appPages + UInt64(stats.wire_count) + UInt64(stats.compressor_page_count)
        return pages * pageSize
    }

    private static func currentPressure() -> Pressure {
        var level: Int32 = 0
        var size = MemoryLayout<Int32>.size
        guard sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0) == 0 else { return .normal }
        switch level {
        case 4: return .critical
        case 2: return .warning
        default: return .normal
        }
    }
}
