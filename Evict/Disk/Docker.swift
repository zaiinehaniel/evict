import AppKit
import Foundation

enum DockerPhase: Equatable {
    case starting, cleaning, stopping
}

enum DockerState: Equatable {
    case notInstalled
    /// Installed but not running; `vmSize` is what its disk image takes on disk.
    case stopped(vmSize: UInt64)
    case running
    case working(DockerPhase)
    case failed(String)
    /// Until the next scan.
    case cleaned
}

/// Docker Desktop, driven through its CLI.
enum Docker {
    struct StartTimedOut: LocalizedError {
        var errorDescription: String? { String(localized: "Docker didn't start in time") }
    }

    static let bundleID = "com.docker.docker"

    static var cli: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/usr/local/bin/docker"),
            URL(fileURLWithPath: "/opt/homebrew/bin/docker"),
            home.appending(path: ".docker/bin/docker"),
            URL(fileURLWithPath: "/Applications/Docker.app/Contents/Resources/bin/docker"),
        ].first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static var app: URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            URL(fileURLWithPath: "/Applications/Docker.app"),
            home.appending(path: "Applications/Docker.app"),
        ].first { FileManager.default.fileExists(atPath: $0.path) }
    }

    static var vmDisk: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Containers/com.docker.docker/Data/vms/0/data/Docker.raw")
    }

    /// Whether the daemon answers.
    static func isRunning() async -> Bool {
        guard let cli else { return false }
        return (try? await CommandLineTool.run(cli, ["info"], timeout: .seconds(5))) != nil
    }

    /// What `docker system df` says is reclaimable, as one item for images and one for build cache.
    static func usage() async throws -> [DiskItem] {
        guard let cli else { return [] }
        let data = try await CommandLineTool.run(cli, ["system", "df", "--format", "json"])
        // One JSON object per line, one line per type.
        var reclaimable: [String: UInt64] = [:]
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let row = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  let type = row["Type"] as? String,
                  let text = row["Reclaimable"] as? String else { continue }
            reclaimable[type] = parseSize(text)
        }
        return [
            DiskItem(id: "docker:images", name: String(localized: "Images"), detail: nil, path: nil,
                     isDirectory: false, size: reclaimable["Images"] ?? 0, lastUsed: nil),
            DiskItem(id: "docker:build-cache", name: String(localized: "Build cache"), detail: nil, path: nil,
                     isDirectory: false, size: reclaimable["Build Cache"] ?? 0, lastUsed: nil),
        ].filter { $0.size > 0 }
    }

    /// Removes unused images older than 30 days, and the build cache.
    static func prune() async throws {
        guard let cli else { return }
        _ = try await CommandLineTool.run(cli, ["image", "prune", "-a", "-f", "--filter", "until=720h"], timeout: .seconds(600))
        _ = try await CommandLineTool.run(cli, ["builder", "prune", "-f"], timeout: .seconds(600))
    }

    /// Opens Docker without bringing it forward, then waits for the daemon.
    static func start() async throws {
        guard let app else { return }
        _ = try await CommandLineTool.run(URL(fileURLWithPath: "/usr/bin/open"), ["-g", "-a", app.path])
        let deadline = ContinuousClock.now + .seconds(120)
        while ContinuousClock.now < deadline {
            try await Task.sleep(for: .seconds(2))
            if await isRunning() { return }
        }
        throw StartTimedOut()
    }

    static func quit() async {
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
            app.terminate()
        }
    }

    /// Parses a size the way `docker system df` prints it: "2.3GB (45%)", "512MB", "0B".
    /// Units are decimal.
    static func parseSize(_ text: String) -> UInt64 {
        let word = text.split(separator: " ").first.map(String.init) ?? ""
        let digits = word.prefix { $0.isNumber || $0 == "." }
        guard let value = Double(digits) else { return 0 }
        let multiplier: Double = switch word.dropFirst(digits.count).lowercased() {
        case "kb": 1e3
        case "mb": 1e6
        case "gb": 1e9
        case "tb": 1e12
        default: 1
        }
        return UInt64(value * multiplier)
    }
}
