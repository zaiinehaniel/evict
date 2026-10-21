import Foundation

enum DiskGroup: String, Codable {
    /// Regenerable data that programs rebuild on their own.
    case appJunk
    /// Things the user made or downloaded that are probably forgotten.
    case yourFiles
}

/// How a category's items leave the disk.
enum DiskRemoval {
    case delete, trash, emptyTrash, simctl, docker
}

enum DiskCategoryID: String, Codable, CaseIterable, Identifiable {
    // App junk, in display order
    case xcodeBuildData, xcodeDeviceSupport, simulators, packageCaches, appCaches, docker
    // Your files, in display order (also the precedence order)
    case installers, xcodeArchives, oldDownloads, largeFiles, nodeModules, trash

    var id: Self { self }

    var group: DiskGroup {
        switch self {
        case .xcodeBuildData, .xcodeDeviceSupport, .simulators, .packageCaches, .appCaches, .docker: .appJunk
        case .installers, .xcodeArchives, .oldDownloads, .largeFiles, .nodeModules, .trash: .yourFiles
        }
    }

    var removal: DiskRemoval {
        switch self {
        case .simulators: .simctl
        case .docker: .docker
        case .trash: .emptyTrash
        default: group == .appJunk ? .delete : .trash
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .xcodeBuildData: "Xcode build data"
        case .xcodeDeviceSupport: "Xcode device support"
        case .simulators: "iOS Simulators"
        case .packageCaches: "Package caches"
        case .appCaches: "App caches"
        case .docker: "Docker"
        case .installers: "Installers"
        case .xcodeArchives: "Xcode archives"
        case .oldDownloads: "Old downloads"
        case .largeFiles: "Large files"
        case .nodeModules: "Stale node_modules"
        case .trash: "Trash"
        }
    }

    var systemImage: String {
        switch self {
        case .xcodeBuildData: "hammer"
        case .xcodeDeviceSupport: "iphone"
        case .simulators: "ipad.and.iphone"
        case .packageCaches: "shippingbox"
        case .appCaches: "app.dashed"
        case .docker: "cube"
        case .installers: "opticaldiscdrive"
        case .xcodeArchives: "archivebox"
        case .oldDownloads: "arrow.down.circle"
        case .largeFiles: "doc.badge.ellipsis"
        case .nodeModules: "folder.badge.minus"
        case .trash: "trash"
        }
    }
}

struct DiskItem: Identifiable, Codable, Hashable {
    /// The path; `simctl:<udid>`; `docker:images` / `docker:build-cache`.
    let id: String
    let name: String
    /// "iOS 17.2", "41 files", …
    let detail: String?
    /// Nil for simulators and Docker, which are removed through their CLIs.
    let path: String?
    let isDirectory: Bool
    let size: UInt64
    let lastUsed: Date?
    /// The cache of a running app: listed, but left out of bulk actions.
    var isOpen = false
}

struct DiskCategory: Identifiable, Codable {
    let id: DiskCategoryID
    var items: [DiskItem]
    /// Sum of the item sizes.
    var total: UInt64
}

struct DiskVolume {
    let available: UInt64
    let total: UInt64

    /// Free space on the home volume, the way Finder counts it (purgeable space included).
    static func current() -> DiskVolume? {
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]
        guard let values = try? FileManager.default.homeDirectoryForCurrentUser.resourceValues(forKeys: keys),
              let available = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else { return nil }
        return DiskVolume(available: UInt64(max(available, 0)), total: UInt64(max(total, 0)))
    }

    var usedFraction: Double {
        total == 0 ? 0 : 1 - Double(available) / Double(total)
    }

    /// Under roughly 10% free.
    var isLow: Bool { available < total / 10 }
}
