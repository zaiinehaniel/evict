import AppKit
import SwiftUI

/// The Disk tab's body: App junk and Your files, one row per category with something in it.
struct DiskOverview: View {
    let diskMonitor: DiskMonitor
    /// Opens a category's items.
    let open: (DiskCategoryID) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let maxHeight: CGFloat = 420
    private static let labelHeight: CGFloat = 28
    private static let filesAccessURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!

    private var appJunk: [DiskCategoryID] {
        DiskCategoryID.allCases.filter { id in
            guard id.group == .appJunk else { return false }
            return id == .docker ? showsDocker : diskMonitor.category(id) != nil
        }
    }

    private var yourFiles: [DiskCategoryID] {
        guard diskMonitor.userFilesEnabled else { return [] }
        return DiskCategoryID.allCases.filter { $0.group == .yourFiles && diskMonitor.category($0) != nil }
    }

    /// Docker gets a row whenever it's installed and has something to say: items, a VM to clean, progress or an error.
    private var showsDocker: Bool {
        switch diskMonitor.docker {
        case .notInstalled: false
        case .running: diskMonitor.category(.docker) != nil
        // A CLI-only install (Colima, OrbStack…) that's off: Evict can't start it, so there's nothing to offer.
        case .stopped: Docker.app != nil
        case .working, .failed, .cleaned: true
        }
    }

    /// The rows that ask for something (the opt-in, or access to a denied folder).
    private var promptCount: Int {
        diskMonitor.userFilesEnabled ? diskMonitor.deniedFolders.count : 1
    }

    var body: some View {
        let appJunk = appJunk
        let yourFiles = yourFiles
        let showsYourFiles = !yourFiles.isEmpty || promptCount > 0

        if !appJunk.isEmpty || showsYourFiles {
            list(appJunk: appJunk, yourFiles: yourFiles, showsYourFiles: showsYourFiles)
        } else if diskMonitor.isScanning {
            // The first scan, with nothing cached yet.
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            EmptyStateCard(title: "Nothing to clear.", message: "Your disk has room to breathe.")
                .padding(14)
        }
    }

    private func list(appJunk: [DiskCategoryID], yourFiles: [DiskCategoryID], showsYourFiles: Bool) -> some View {
        let labels = (appJunk.isEmpty ? 0 : 1) + (showsYourFiles ? 1 : 0)
        let rows = appJunk.count + yourFiles.count
        let prompts = showsYourFiles ? promptCount : 0
        let height = CGFloat(labels) * Self.labelHeight + CGFloat(rows) * DiskCategoryRow.height
            + CGFloat(prompts) * DiskPromptRow.height + 8

        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !appJunk.isEmpty {
                    groupLabel("App junk", showsDeleteHint: false)
                    ForEach(appJunk) { id in
                        DiskCategoryRow(id: id, diskMonitor: diskMonitor) { open(id) }
                            .transition(.opacity)
                    }
                }
                if showsYourFiles {
                    groupLabel("Your files", showsDeleteHint: yourFiles.contains { $0.removal == .trash })
                    if !diskMonitor.userFilesEnabled {
                        DiskPromptRow(systemImage: "folder.badge.questionmark",
                                      title: "Check your files",
                                      caption: "Downloads, Desktop and Documents — macOS will ask for access") {
                            diskMonitor.enableUserFiles()
                        }
                    } else {
                        ForEach(diskMonitor.deniedFolders, id: \.self) { folder in
                            DiskPromptRow(systemImage: "lock",
                                          title: "Allow access to \(String(localized: folder.title)) in System Settings",
                                          caption: nil) {
                                NSWorkspace.shared.open(Self.filesAccessURL)
                            }
                        }
                        ForEach(yourFiles) { id in
                            DiskCategoryRow(id: id, diskMonitor: diskMonitor) { open(id) }
                                .transition(.opacity)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: appJunk + yourFiles)
        }
        .frame(height: min(height, Self.maxHeight))
    }

    private func groupLabel(_ title: LocalizedStringKey, showsDeleteHint: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if showsDeleteHint {
                OptionDeleteHint()
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity, minHeight: Self.labelHeight, maxHeight: Self.labelHeight, alignment: .bottom)
    }
}

/// "⌥ deletes permanently" — teaches that holding Option turns Move to Trash into Delete.
struct OptionDeleteHint: View {
    var body: some View {
        Text("⌥ deletes permanently")
            .font(.caption)
            .foregroundStyle(.tertiary)
            .lineLimit(1)
            .accessibilityLabel("Hold Option to delete permanently")
    }
}

/// A row that asks for something instead of listing a category: the Your files opt-in, or access to a denied folder.
private struct DiskPromptRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let caption: LocalizedStringKey?
    let action: () -> Void

    /// Room for two lines of title or caption, since the copy is longer than a category's.
    static let height: CGFloat = 50

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13))
                    .foregroundStyle(.tint)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .foregroundStyle(.tint)
                        .lineLimit(caption == nil ? 2 : 1)
                    if let caption {
                        Text(caption)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: Self.height)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(.primary.opacity(isHovered ? 0.06 : 0))
                    .padding(.horizontal, 6)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { isHovered = hovering }
        }
    }
}
