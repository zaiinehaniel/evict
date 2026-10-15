import SwiftUI

/// "In the background · 7.3 GB" — memory held outside the Dock, for reference.
/// Collapsed by default; Evict never closes these.
struct BackgroundSection: View {
    let groups: [BackgroundGroup]

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
            .help("Menu bar apps, helpers and agents. Shown for reference: Evict never closes them.")
            .accessibilityLabel("In the background, \(Format.memory(total))")
            .accessibilityValue(isExpanded ? Text("Expanded") : Text("Collapsed"))

            if isExpanded {
                ForEach(groups.prefix(Self.visibleRows)) { group in
                    row(group)
                }
                .transition(.opacity)
            }
        }
        .padding(.bottom, isExpanded ? 6 : 0)
    }

    private func row(_ group: BackgroundGroup) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: group.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) }
                  ?? NSWorkspace.shared.icon(for: .unixExecutable))
                .resizable()
                .frame(width: 18, height: 18)
                .padding(.horizontal, 3)
            Text(group.name)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            Text(Format.memory(group.memory))
                .font(.callout)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 26)
        .help(group.bundlePath ?? group.name)
        .accessibilityElement(children: .combine)
    }
}
