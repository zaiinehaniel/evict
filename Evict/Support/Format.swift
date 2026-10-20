import Foundation

enum Format {
    private static let mebibyte = 1_048_576.0
    private static let gibibyte = 1_073_741_824.0

    /// "820 MB", "1.4 GB" — binary units, like Activity Monitor.
    static func memory(_ bytes: UInt64) -> String {
        let megabytes = Double(bytes) / mebibyte
        if megabytes < 1 { return "<1 MB" }
        if megabytes < 1000 { return "\(Int(megabytes.rounded())) MB" }
        return gigabytes(bytes) + " GB"
    }

    static func gigabytes(_ bytes: UInt64, fractionDigits: Int = 1) -> String {
        (Double(bytes) / gibibyte).formatted(.number.precision(.fractionLength(fractionDigits)))
    }

    /// "820 MB", "14.2 GB", "1.2 TB" — decimal units, like Finder (1 GB = 10⁹ bytes).
    static func disk(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        if bytes == 0 { return "0 MB" }
        if value < 1e6 { return "<1 MB" }
        if value < 999.5e6 { return "\(Int((value / 1e6).rounded())) MB" }
        if value < 999.95e9 { return (value / 1e9).formatted(.number.precision(.fractionLength(1))) + " GB" }
        return (value / 1e12).formatted(.number.precision(.fractionLength(1))) + " TB"
    }

    /// Whole decimal gigabytes, "412" — for the disk gauge.
    static func diskGigabytes(_ bytes: UInt64) -> String {
        (Double(bytes) / 1e9).formatted(.number.precision(.fractionLength(0)))
    }

    /// "45m", "3h 12m", "2d 4h".
    static func duration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes < 60 { return "\(max(minutes, 1))m" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "\(hours)h" : "\(hours)h \(minutes % 60)m" }
        return hours % 24 == 0 ? "\(hours / 24)d" : "\(hours / 24)d \(hours % 24)h"
    }

    /// "30 minutes", "1 hour", "8 hours" — localized.
    static func longDuration(minutes: Int) -> String {
        Duration.seconds(minutes * 60).formatted(.units(allowed: [.hours, .minutes], width: .wide))
    }

    /// "Just used", "Used 25m ago", or — once past the idle limit — "Idle 4h 12m".
    static func idleLabel(_ interval: TimeInterval, pastLimit: Bool) -> String {
        if pastLimit { return String(localized: "Idle \(duration(interval))") }
        return interval < 60 ? String(localized: "Just used") : String(localized: "Used \(duration(interval)) ago")
    }
}
