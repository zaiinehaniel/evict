import SwiftUI

/// One category on the Disk tab: what it is, how big, and a one-click action that confirms inline.
/// Tapping the row opens the category's items.
struct DiskCategoryRow: View {
    let id: DiskCategoryID
    let diskMonitor: DiskMonitor
    let open: () -> Void

    static let height: CGFloat = 40

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var animation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.15) }
    private var category: DiskCategory? { diskMonitor.category(id) }
    private var isDocker: Bool { id == .docker }
    private var isWorking: Bool {
        if isDocker, case .working = diskMonitor.docker { return true }
        return diskMonitor.working.contains(id)
    }

    private var confirmation: DiskConfirmation? {
        guard case .category(id, _) = diskMonitor.pendingConfirmation else { return nil }
        return diskMonitor.pendingConfirmation
    }

    /// Docker's items only exist while it runs; stopped, there's nothing to drill into.
    private var canOpen: Bool { category != nil }

    private var size: UInt64? {
        if let category { return category.total }
        if case .stopped(let vmSize) = diskMonitor.docker, isDocker, vmSize > 0 { return vmSize }
        return nil
    }

    // MARK: Action

    private enum Action {
        /// Asks to confirm a removal; `permanently` deletes what would otherwise go to the Trash.
        case remove(permanently: Bool)
        /// Docker: prunes right away, starting Docker first when `opens`.
        case clean(opens: Bool)
    }

    private var action: Action? {
        if isDocker {
            switch diskMonitor.docker {
            case .running: return category == nil ? nil : .clean(opens: false)
            // Without Docker Desktop there's nothing Evict can start.
            case .stopped: return Docker.app == nil ? nil : .clean(opens: true)
            case .failed: return category == nil ? nil : .clean(opens: false)
            case .notInstalled, .working, .cleaned: return nil
            }
        }
        guard category != nil else { return nil }
        return .remove(permanently: id.removal != .trash || OptionKey.shared.isDown)
    }

    private func title(for action: Action) -> LocalizedStringKey {
        switch action {
        case .clean(let opens): opens ? "Open and clean" : "Clean"
        case .remove(let permanently): removalTitle(permanently: permanently)
        }
    }

    private func removalTitle(permanently: Bool) -> LocalizedStringKey {
        switch id.removal {
        case .trash: permanently ? "Delete" : "Move to Trash"
        case .emptyTrash: "Empty"
        case .delete, .simctl, .docker: "Delete"
        }
    }

    private var hasSelection: Bool { !diskMonitor.selection(in: id).isEmpty }

    private func perform(_ action: Action) {
        switch action {
        case .remove(let permanently):
            withAnimation(animation) { diskMonitor.pendingConfirmation = .category(id, permanently: permanently) }
        case .clean:
            diskMonitor.pendingConfirmation = nil
            Task { await diskMonitor.cleanDocker() }
        }
    }

    private func confirm(permanently: Bool) {
        let items = diskMonitor.selection(in: id)
        Task { await diskMonitor.remove(items, from: id, permanently: permanently) }
    }

    // MARK: Detail

    private enum Tone { case normal, failure }

    /// "41 items · 2 open", "not running", "Starting Docker…", "3 items couldn't be removed".
    private var detail: (text: String, tone: Tone)? {
        if isDocker {
            switch diskMonitor.docker {
            case .stopped: return (String(localized: "not running"), .normal)
            case .working(.starting): return (String(localized: "Starting Docker…"), .normal)
            case .working(.cleaning): return (String(localized: "Cleaning…"), .normal)
            case .working(.stopping): return (String(localized: "Stopping Docker…"), .normal)
            case .cleaned: return (String(localized: "Cleaned"), .normal)
            case .failed(let message): return (message, .failure)
            case .notInstalled, .running: break
            }
        }
        if let failed = diskMonitor.failures[id], failed > 0 {
            return (String(AttributedString(localized: "^[\(failed) items](inflect: true) couldn't be removed").characters), .failure)
        }
        guard let category else { return nil }
        let count = String(AttributedString(localized: "^[\(category.items.count) items](inflect: true)").characters)
        let openCount = category.items.count(where: \.isOpen)
        guard openCount > 0 else { return (count, .normal) }
        return (String(localized: "\(count) · \(openCount) open"), .normal)
    }

    // MARK: Body

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: id.systemImage)
                .font(.system(size: 13))
                .foregroundStyle(Brand.indigo)
                .frame(width: 24, height: 24)
                .background(Brand.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 1) {
                Text(id.title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let detail {
                    Text(detail.text)
                        .font(.caption)
                        .monospacedDigit()
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .foregroundStyle(detail.tone == .failure ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .help(detail.text)
                }
            }

            Spacer(minLength: 8)

            if case .category(_, let permanently) = confirmation {
                confirmButtons(permanently: permanently)
                    .transition(.opacity)
            } else {
                if let size {
                    Text(Format.disk(size))
                        .monospacedDigit()
                        .foregroundStyle(category == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                }
                if isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity)
                } else if let action {
                    Button(title(for: action)) { perform(action) }
                        .controlSize(.small)
                        .disabled(!isDocker && !hasSelection)
                }
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .opacity(canOpen ? 1 : 0)
            }
        }
        .animation(animation, value: isWorking)
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.primary.opacity((isHovered && canOpen) || confirmation != nil ? 0.06 : 0))
                .padding(.horizontal, 6)
        }
        .contentShape(Rectangle())
        .onTapGesture { openIfPossible() }
        .onHover { hovering in
            withAnimation(animation) { isHovered = hovering }
        }
        .accessibilityElement(children: confirmation == nil ? .ignore : .contain)
        .accessibilityLabel(Text(id.title))
        .accessibilityValue(accessibilityValue)
        .accessibilityActions {
            if let action, isDocker || hasSelection, !isWorking {
                Button(title(for: action)) { perform(action) }
            }
            if canOpen {
                Button("Show items", action: open)
            }
        }
    }

    private func openIfPossible() {
        guard canOpen, confirmation == nil else { return }
        open()
    }

    private func confirmButtons(permanently: Bool) -> some View {
        HStack(spacing: 6) {
            Button("Cancel") {
                withAnimation(animation) { diskMonitor.pendingConfirmation = nil }
            }
            .keyboardShortcut(.cancelAction)

            Button(removalTitle(permanently: permanently)) { confirm(permanently: permanently) }
                .keyboardShortcut(.defaultAction)
                .tint(permanently ? .red : nil)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
    }

    private var accessibilityValue: String {
        var parts: [String] = []
        if let size { parts.append(Format.disk(size)) }
        if let detail { parts.append(detail.text) }
        return parts.joined(separator: ", ")
    }
}
