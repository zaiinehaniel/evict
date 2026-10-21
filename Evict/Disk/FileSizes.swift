import CoreServices
import Foundation

enum FileSizes {
    /// Allocated size, the way Finder counts it. Recursive for folders; symlinks count
    /// for themselves and are never followed.
    static func allocatedSize(of url: URL) -> UInt64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        func size(_ url: URL) -> UInt64 {
            let values = try? url.resourceValues(forKeys: keys)
            return UInt64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else {
            return size(url)
        }
        // The enumerator skips the root itself, and doesn't follow symlinks to folders.
        var total = size(url)
        for case let child as URL in enumerator {
            if Task.isCancelled { break }
            total += size(child)
        }
        return total
    }

    /// The newest modification date in the item, recursing into folders.
    static func newestModification(in url: URL) -> Date? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        var newest = try? url.resourceValues(forKeys: Set(keys)).contentModificationDate
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else {
            return newest
        }
        for case let child as URL in enumerator {
            if Task.isCancelled { break }
            guard let date = try? child.resourceValues(forKeys: Set(keys)).contentModificationDate else { continue }
            if newest.map({ date > $0 }) ?? true { newest = date }
        }
        return newest
    }

    /// The later of Spotlight's last-used date and the modification date.
    static func lastUsed(_ url: URL) -> Date? {
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let opened = MDItemCreateWithURL(nil, url as CFURL)
            .flatMap { MDItemCopyAttribute($0, kMDItemLastUsedDate) as? Date }
        return [modified, opened].compactMap { $0 }.max()
    }
}
