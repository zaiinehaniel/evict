import Darwin
import Foundation

/// Removes what a scan listed, re-checking each item right before it goes.
enum DiskRemover {
    private static let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    private static let trash = home + "/.Trash"
    private static let xcrun = URL(filePath: "/usr/bin/xcrun")

    /// Re-validates, then removes. False if skipped or failed.
    static func remove(_ item: DiskItem, removal: DiskRemoval, permanently: Bool) async -> Bool {
        switch removal {
        case .docker:
            // Docker is cleaned through its CLI by `DiskMonitor.cleanDocker()`.
            return false
        case .simctl:
            return await deleteSimulator(item)
        case .delete, .trash, .emptyTrash:
            guard let url = validatedURL(item, removal: removal) else { return false }
            do {
                if removal == .trash, !permanently {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                } else {
                    try FileManager.default.removeItem(at: url)
                }
                return true
            } catch {
                return false
            }
        }
    }

    // MARK: Files

    /// The item's URL if it's still what the scan found: a literal path under the home folder,
    /// outside every cloud folder, reached without symlinks, and still the same kind of item.
    private static func validatedURL(_ item: DiskItem, removal: DiskRemoval) -> URL? {
        guard let path = item.path, path == item.id, path.hasPrefix("/") else { return nil }
        // No "." or ".." and no empty components, so the path means exactly what it says.
        let components = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard !components.isEmpty, !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            return nil
        }
        let url = URL(filePath: path, directoryHint: item.isDirectory ? .isDirectory : .notDirectory)
        guard !HomeExclusions.isCloudOrOutsideHome(url) else { return nil }

        // No folder above it is a symlink: resolving the parent changes nothing.
        guard let slash = path.lastIndex(of: "/") else { return nil }
        let parent = String(path[..<slash])
        guard resolved(parent) == parent else { return nil }
        // Emptying the Trash only ever removes the Trash's own entries.
        if removal == .emptyTrash, parent != trash { return nil }

        // The item itself still exists, isn't a symlink, and is still a file or a folder as scanned.
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        let type = info.st_mode & S_IFMT
        guard type != S_IFLNK, (type == S_IFDIR) == item.isDirectory else { return nil }
        return url
    }

    /// The path with every symlink resolved, or nil when it doesn't exist.
    private static func resolved(_ path: String) -> String? {
        guard let pointer = realpath(path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    // MARK: Simulators

    /// `simctl delete` on the item's UDID, if it's still one of the unavailable simulators.
    private static func deleteSimulator(_ item: DiskItem) async -> Bool {
        let prefix = "simctl:"
        // A parsed UUID, never a keyword like "all" or "unavailable".
        guard item.path == nil, item.id.hasPrefix(prefix),
              let udid = UUID(uuidString: String(item.id.dropFirst(prefix.count))) else { return false }
        guard let data = try? await CommandLineTool.run(xcrun, ["simctl", "list", "devices", "unavailable", "-j"]),
              let list = try? JSONDecoder().decode(SimulatorList.self, from: data),
              let listed = list.devices.values.joined().first(where: { UUID(uuidString: $0.udid) == udid })
        else { return false }
        do {
            _ = try await CommandLineTool.run(xcrun, ["simctl", "delete", listed.udid], timeout: .seconds(120))
            return true
        } catch {
            return false
        }
    }

    private struct SimulatorList: Decodable {
        struct Device: Decodable {
            let udid: String
        }
        let devices: [String: [Device]]
    }
}
