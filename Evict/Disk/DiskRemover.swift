import Darwin
import Foundation

/// Removes what a scan listed, re-checking each item right before it goes.
enum DiskRemover {
    enum Outcome {
        case removed
        /// Already gone from the disk: nothing to remove, nothing went wrong.
        case gone
        /// Skipped by a check, or the removal itself failed.
        case failed
    }

    private static let xcrun = URL(filePath: "/usr/bin/xcrun")

    /// Re-validates, then removes the item the way `category` says.
    static func remove(_ item: DiskItem, from category: DiskCategoryID, permanently: Bool) async -> Outcome {
        let removal = category.removal
        switch removal {
        case .docker:
            // Docker is cleaned through its CLI by `DiskMonitor.cleanDocker()`.
            return .failed
        case .simctl:
            return await deleteSimulator(item)
        case .delete, .trash, .emptyTrash:
            let url: URL
            switch validate(item, in: category) {
            case .removable(let checked): url = checked
            case .gone: return .gone
            case .refused: return .failed
            }
            do {
                if removal == .trash, !permanently {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                } else {
                    try FileManager.default.removeItem(at: url)
                }
                return .removed
            } catch {
                // Removed by something else in the meantime.
                return exists(url.path) ? .failed : .gone
            }
        }
    }

    // MARK: Files

    private enum Validation {
        case removable(URL)
        case gone
        case refused
    }

    /// Whether the item is still what the scan found: a literal path where `category` lists items,
    /// under the home folder and on its volume, outside every cloud folder, reached without symlinks,
    /// and the same kind of item.
    private static func validate(_ item: DiskItem, in category: DiskCategoryID) -> Validation {
        guard let path = item.path, path == item.id, path.hasPrefix("/") else { return .refused }
        // No "." or ".." and no empty components, so the path means exactly what it says.
        let components = path.split(separator: "/", omittingEmptySubsequences: false).dropFirst()
        guard !components.isEmpty, !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) else {
            return .refused
        }
        guard DiskRoots.contains(path, isDirectory: item.isDirectory, for: category) else { return .refused }
        // `.notDirectory`: a trailing "/" would make the system follow a symlink at the end of the path.
        let url = URL(filePath: path, directoryHint: .notDirectory)
        guard !HomeExclusions.isCloudOrOutsideHome(url) else { return .refused }

        var info = stat()
        guard lstat(path, &info) == 0 else { return errno == ENOENT ? .gone : .refused }
        // Never on another volume mounted under ~, which the scan doesn't walk.
        guard HomeExclusions.isHomeVolume(info.st_dev) else { return .refused }
        // No folder above it is a symlink: resolving the parent changes nothing.
        guard let slash = path.lastIndex(of: "/") else { return .refused }
        let parent = String(path[..<slash])
        guard resolved(parent) == parent else { return .refused }

        let type = info.st_mode & S_IFMT
        if type == S_IFLNK {
            // A symlink in the Trash is a trashed item of its own: emptying removes the link, never
            // what it points to. Anywhere else the item was swapped since the scan.
            return category.removal == .emptyTrash ? .removable(url) : .refused
        }
        guard (type == S_IFDIR) == item.isDirectory else { return .refused }
        return .removable(url)
    }

    private static func exists(_ path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 || errno != ENOENT
    }

    /// The path with every symlink resolved, or nil when it doesn't exist.
    private static func resolved(_ path: String) -> String? {
        guard let pointer = realpath(path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    // MARK: Simulators

    /// `simctl delete` on the item's UDID, if it's still one of the unavailable simulators.
    private static func deleteSimulator(_ item: DiskItem) async -> Outcome {
        let prefix = "simctl:"
        // A parsed UUID, never a keyword like "all" or "unavailable".
        guard item.path == nil, item.id.hasPrefix(prefix),
              let udid = UUID(uuidString: String(item.id.dropFirst(prefix.count))),
              let unavailable = await simulators(["unavailable"]) else { return .failed }
        guard let listed = unavailable.first(where: { UUID(uuidString: $0) == udid }) else {
            // Not unavailable any more: gone if simctl no longer knows it, left alone if it works again.
            guard let all = await simulators([]) else { return .failed }
            return all.contains { UUID(uuidString: $0) == udid } ? .failed : .gone
        }
        do {
            _ = try await CommandLineTool.run(xcrun, ["simctl", "delete", listed], timeout: .seconds(120))
            return .removed
        } catch {
            return .failed
        }
    }

    /// The UDIDs `simctl list devices <filter>` prints, or nil if it can't be listed.
    private static func simulators(_ filter: [String]) async -> [String]? {
        guard let data = try? await CommandLineTool.run(xcrun, ["simctl", "list", "devices"] + filter + ["-j"]),
              let list = try? JSONDecoder().decode(SimulatorList.self, from: data) else { return nil }
        return list.devices.values.joined().map(\.udid)
    }

    private struct SimulatorList: Decodable {
        struct Device: Decodable {
            let udid: String
        }
        let devices: [String: [Device]]
    }
}
