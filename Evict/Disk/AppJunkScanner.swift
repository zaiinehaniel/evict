import AppKit
import Foundation

enum AppJunkScanner {
    private static let minimumCacheSize: UInt64 = 1_048_576

    /// Everything in `id` that can go. Docker has its own scanner.
    static func scan(_ id: DiskCategoryID, runningBundleIDs: Set<String>) async -> [DiskItem] {
        switch id {
        case .xcodeBuildData: await buildData()
        case .xcodeDeviceSupport: await deviceSupport()
        case .simulators: await simulators()
        case .packageCaches: await packageCacheItems()
        case .appCaches: await appCaches(runningBundleIDs: runningBundleIDs)
        default: []
        }
    }

    // MARK: Categories

    private static func buildData() async -> [DiskItem] {
        let folders = folders(in: DiskRoots.derivedData).filter { $0.lastPathComponent != "ModuleCache.noindex" }
        return await items(for: folders) { url in
            (name: projectName(url.lastPathComponent), detail: nil)
        }
    }

    private static func deviceSupport() async -> [DiskItem] {
        let platforms = folders(in: DiskRoots.xcode).filter { $0.lastPathComponent.hasSuffix(DiskRoots.deviceSupportSuffix) }
        var details: [URL: String] = [:]
        var all: [URL] = []
        for platform in platforms {
            let name = platform.lastPathComponent.replacingOccurrences(of: " " + DiskRoots.deviceSupportSuffix, with: "")
            for folder in folders(in: platform) {
                details[folder] = name
                all.append(folder)
            }
        }
        let platformOf = details
        return await items(for: all) { url in
            (name: url.lastPathComponent, detail: platformOf[url])
        }
    }

    private static func simulators() async -> [DiskItem] {
        guard let data = try? await CommandLineTool.run(URL(filePath: "/usr/bin/xcrun"),
                                                        ["simctl", "list", "devices", "unavailable", "-j"]),
              let list = try? JSONDecoder().decode(SimulatorList.self, from: data) else { return [] }
        let devices = DiskRoots.simulatorDevices
        var found: [(udid: String, name: String, runtime: String)] = []
        for (runtime, entries) in list.devices {
            for entry in entries { found.append((entry.udid, entry.name, prettyRuntime(runtime))) }
        }
        return await withTaskGroup(of: DiskItem?.self) { group in
            for device in found {
                group.addTask {
                    if Task.isCancelled { return nil }
                    let url = devices.appending(path: device.udid)
                    return DiskItem(id: "simctl:\(device.udid)", name: device.name, detail: device.runtime, path: nil,
                                    isDirectory: true, size: FileSizes.allocatedSize(of: url),
                                    lastUsed: FileSizes.newestModification(in: url))
                }
            }
            var result: [DiskItem] = []
            for await item in group { if let item { result.append(item) } }
            return result
        }
    }

    private static func packageCacheItems() async -> [DiskItem] {
        let existing = DiskRoots.packageCaches
            .filter { FileManager.default.fileExists(atPath: $0.url.path) }
        let names = Dictionary(uniqueKeysWithValues: existing.map { ($0.url, $0.name) })
        return await items(for: existing.map(\.url)) { url in
            (name: names[url] ?? url.lastPathComponent, detail: nil)
        }
    }

    private static func appCaches(runningBundleIDs: Set<String>) async -> [DiskItem] {
        let packagePaths = Set(DiskRoots.packageCaches.map(\.url.path))
        let candidates = folders(in: DiskRoots.caches).filter { url in
            !url.lastPathComponent.hasPrefix(DiskRoots.appleCachePrefix) && !packagePaths.contains(url.path)
        }
        let all = await items(for: candidates, minimumSize: minimumCacheSize) { url in
            let folder = url.lastPathComponent
            let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: folder)
            return (name: app?.deletingPathExtension().lastPathComponent ?? folder,
                    detail: nil)
        }
        return all.map { item in
            var item = item
            item.isOpen = runningBundleIDs.contains(URL(filePath: item.id).lastPathComponent)
            return item
        }
    }

    // MARK: Helpers

    /// The visible sub-folders of `url`, or none when it doesn't exist.
    private static func folders(in url: URL) -> [URL] {
        let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        return (contents ?? []).filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    /// Sizes the folders concurrently. Items under `minimumSize` are dropped.
    private static func items(for urls: [URL], minimumSize: UInt64 = 0,
                              describe: @escaping @Sendable (URL) -> (name: String, detail: String?)) async -> [DiskItem] {
        await withTaskGroup(of: DiskItem?.self) { group in
            for url in urls {
                group.addTask {
                    if Task.isCancelled { return nil }
                    let size = FileSizes.allocatedSize(of: url)
                    guard size >= minimumSize, size > 0 else { return nil }
                    let (name, detail) = describe(url)
                    return DiskItem(id: url.path, name: name, detail: detail, path: url.path, isDirectory: true,
                                    size: size, lastUsed: FileSizes.lastUsed(url))
                }
            }
            var result: [DiskItem] = []
            for await item in group { if let item { result.append(item) } }
            return result
        }
    }

    /// "Evict-abcd1234" → "Evict".
    private static func projectName(_ folder: String) -> String {
        guard let dash = folder.lastIndex(of: "-") else { return folder }
        return String(folder[..<dash])
    }

    /// "com.apple.CoreSimulator.SimRuntime.iOS-17-2" → "iOS 17.2".
    private static func prettyRuntime(_ identifier: String) -> String {
        let tail = identifier.split(separator: ".").last.map(String.init) ?? identifier
        let parts = tail.split(separator: "-").map(String.init)
        guard let platform = parts.first else { return identifier }
        let version = parts.dropFirst().joined(separator: ".")
        return version.isEmpty ? platform : "\(platform) \(version)"
    }

    private struct SimulatorList: Decodable {
        struct Device: Decodable {
            let udid: String
            let name: String
        }
        let devices: [String: [Device]]
    }
}
