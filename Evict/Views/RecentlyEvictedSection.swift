import SwiftUI

/// The last few apps Evict closed, each one click away from coming back.
struct RecentlyEvictedSection: View {
    let items: [EvictedApp]
    let now: Date
    let reopen: (EvictedApp) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recently evicted")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 8)
                .padding(.bottom, 2)
                .accessibilityAddTraits(.isHeader)

            ForEach(items) { item in
                row(item)
            }
        }
        .padding(.bottom, 4)
    }

    private func row(_ item: EvictedApp) -> some View {
        HStack(spacing: 10) {
            Image(nsImage: item.bundlePath.map { NSWorkspace.shared.icon(forFile: $0) } ?? NSWorkspace.shared.icon(for: .application))
                .resizable()
                .frame(width: 20, height: 20)
                .opacity(0.6)
                .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.callout)
                    .lineLimit(1)
                Text(detail(item))
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("Reopen") { reopen(item) }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(item.bundlePath == nil)
                .accessibilityLabel("Reopen \(item.name)")
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .accessibilityElement(children: .combine)
    }

    private func detail(_ item: EvictedApp) -> String {
        let ago = String(localized: "\(Format.duration(now.timeIntervalSince(item.date))) ago")
        guard let freed = item.freed else { return ago }
        return "\(String(localized: "Freed \(Format.memory(freed))")) · \(ago)"
    }
}
