import Foundation

/// The home folders macOS asks permission for (TCC) before an app can read them.
enum ProtectedFolder: String, CaseIterable, Codable {
    case downloads, desktop, documents

    var url: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return switch self {
        case .downloads: home.appending(path: "Downloads")
        case .desktop: home.appending(path: "Desktop")
        case .documents: home.appending(path: "Documents")
        }
    }

    var title: LocalizedStringResource {
        switch self {
        case .downloads: "Downloads"
        case .desktop: "Desktop"
        case .documents: "Documents"
        }
    }

    /// Lists the folder; the first call is what triggers the macOS prompt. False on a permission error.
    nonisolated func hasAccess() -> Bool {
        do {
            _ = try FileManager.default.contentsOfDirectory(atPath: url.path)
            return true
        } catch {
            let code = (error as NSError).code
            let underlying = ((error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError)?.code
            let denied = [Int(EPERM), Int(EACCES)]
            return !(code == NSFileReadNoPermissionError || denied.contains(code) || underlying.map(denied.contains) == true)
        }
    }
}
