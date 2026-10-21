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
        drainingEach(enumerator) { total += size($0) }
        return total
    }

    /// The newest modification date in the item, recursing into folders.
    static func newestModification(in url: URL) -> Date? {
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        var newest = try? url.resourceValues(forKeys: Set(keys)).contentModificationDate
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else {
            return newest
        }
        drainingEach(enumerator) { child in
            guard let date = try? child.resourceValues(forKeys: Set(keys)).contentModificationDate else { return }
            if newest.map({ date > $0 }) ?? true { newest = date }
        }
        return newest
    }

    /// Visits every URL until the enumerator runs out or the task is cancelled, draining an
    /// autorelease pool every `batch` items. The enumerator's URLs and resource values are
    /// autoreleased, and a synchronous walk in a task never drains on its own: without this
    /// a scan of the home folder holds every URL it saw until it ends (hundreds of MB).
    static func drainingEach(_ enumerator: FileManager.DirectoryEnumerator, batch: Int = 500, _ body: (URL) -> Void) {
        var exhausted = false
        while !exhausted, !Task.isCancelled {
            autoreleasepool {
                for _ in 0..<batch {
                    guard let url = enumerator.nextObject() as? URL else {
                        exhausted = true
                        return
                    }
                    body(url)
                }
            }
        }
    }

    /// The later of Spotlight's last-used date and the modification date.
    static func lastUsed(_ url: URL) -> Date? {
        let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        let opened = MDItemCreateWithURL(nil, url as CFURL)
            .flatMap { MDItemCopyAttribute($0, kMDItemLastUsedDate) as? Date }
        return [modified, opened].compactMap { $0 }.max()
    }
}
