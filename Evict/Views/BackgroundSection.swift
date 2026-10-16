import SwiftUI

/// "In the background · 7.3 GB" — memory held outside the Dock. Collapsed by
/// default; menu bar apps can be quit from here, helpers and agents can't.
struct BackgroundSection: View {
    let groups: [BackgroundGroup]
    let monitor: AppMonitor

    @AppStorage("showBackgroundProcesses") private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let visibleRows = 5
    private var total: UInt64 { groups.reduce(0) { $0 + $1.memory } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text("In the background")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(Format.memory(total))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .help("Menu bar apps, helpers and agents. Menu bar apps can be quit; helpers and agents are shown for reference.")
            .accessibilityLabel("In the background, \(Format.memory(total))")
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))

            if isExpanded {
                ForEach(groups.prefix(Self.visibleRows)) { group in
                    BackgroundRow(group: group, monitor: monitor)
                }
                .transition(.opacity)
            }
        }
        .padding(.bottom, isExpanded ? 6 : 0)
    }
}

private struct BackgroundRow: View {
    let group: BackgroundGroup
    let monitor: AppMonitor

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isQuittable: Bool { !group.appPIDs.isEmpty }
    private var isQuitting: Bool { monitor.isQuitting(group) }
    private var isConfirming: Bool { monitor.pendingConfirmation == .quitBackground(group.id) }
    private var animation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.15) }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: group.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
                  ?? NSWorkspace.shared.icon(for: .unixExecutable))
                .resizable()
                .frame(width: 18, height: 18)
                .padding(.horizontal, 3)
            Text(isQuitting ? "\(group.name) · \(String(localized: "Quitting…"))" : group.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)

            if isConfirming {
                confirmButtons
                    .transition(.opacity)
            } else {
                if isQuitting {
                    ProgressView()
                        .controlSize(.mini)
                        .transition(.opacity)
                } else if isHovered, isQuittable {
                    Button("Quit \(group.name)", systemImage: "xmark.circle", action: ask)
                        .labelStyle(.iconOnly)
                        .frame(width: 20, height: 20)
                        .contentShape(Rectangle())
                        .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Quit \(group.name)")
                    .transition(.opacity)
                }
                Text(Format.memory(group.memory))
                    .font(.callout)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .opacity(isQuitting ? 0.6 : 1)
        .animation(animation, value: isQuitting)
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.primary.opacity(isQuittable && (isHovered || isConfirming) ? 0.06 : 0))
                .padding(.horizontal, 6)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(animation) { isHovered = hovering }
        }
        .contextMenu {
            if isQuittable {
                Button("Quit") { ask() }
            }
        }
        .help(group.bundlePath ?? group.name)
        .accessibilityElement(children: isConfirming ? .contain : .combine)
        .accessibilityActions {
            if isQuittable { Button("Quit", action: ask) }
        }
    }

    private func ask() {
        withAnimation(animation) { monitor.pendingConfirmation = .quitBackground(group.id) }
    }

    private var confirmButtons: some View {
        HStack(spacing: 6) {
            Button("Cancel") {
                withAnimation(animation) { monitor.pendingConfirmation = nil }
            }
            .keyboardShortcut(.cancelAction)

            Button("Quit") { monitor.quit(group) }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
        }
        .controlSize(.mini)
    }
}
