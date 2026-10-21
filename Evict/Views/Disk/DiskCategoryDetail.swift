import AppKit
import QuickLook
import SwiftUI

/// One Disk category's items, shown in place of the overview: everything starts checked
/// except what the user kept, and unchecking an item keeps it for good.
///
/// Works on a snapshot taken when it opens, so a background scan never moves or drops rows
/// under the pointer; the footer re-checks the selection against the scan when clicked.
struct DiskCategoryDetail: View {
    let category: DiskCategory
    let diskMonitor: DiskMonitor
    let close: () -> Void

    @State private var items: [DiskItem]
    @State private var sort: ItemSort = .size
    /// The highlighted row: Space previews it, the arrow keys move it.
    @State private var selected: String?
    @State private var previewURL: URL?
    @FocusState private var listFocused: Bool

    private static let maxListHeight: CGFloat = 420

    init(category: DiskCategory, diskMonitor: DiskMonitor, close: @escaping () -> Void) {
        self.category = category
        self.diskMonitor = diskMonitor
        self.close = close
        _items = State(initialValue: category.items)
    }

    private var id: DiskCategoryID { category.id }
    /// Docker is cleaned as a whole, so its items have no checkboxes.
    private var isDocker: Bool { id.removal == .docker }
    private var total: UInt64 { items.reduce(0) { $0 + $1.size } }

    private func isChecked(_ item: DiskItem) -> Bool {
        !item.isOpen && !diskMonitor.kept.contains(item.id)
    }

    private var checkedItems: [DiskItem] { items.filter(isChecked) }

    private var sortedItems: [DiskItem] {
        switch sort {
        case .size:
            return items.sorted { $0.size > $1.size }
        case .age:
            // Oldest first; items with no date go last.
            return items.sorted { a, b in
                switch (a.lastUsed, b.lastUsed) {
                case let (a?, b?): a < b
                case (.some, nil): true
                case (nil, .some): false
                case (nil, nil): a.size > b.size
                }
            }
        }
    }

    /// Simulators and Docker live behind their CLIs: nothing to preview or reveal.
    private func fileURL(_ item: DiskItem) -> URL? {
        guard id.removal != .simctl, !isDocker, let path = item.path else { return nil }
        return URL(fileURLWithPath: path, isDirectory: item.isDirectory)
    }

    // MARK: Body

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if !isDocker { controls }
            Divider()
            list
            Divider()
            footer
        }
    }

    private var topBar: some View {
        HStack(spacing: 8) {
            Button(action: close) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.left")
                        .fontWeight(.semibold)
                    Text("Disk")
                }
                .foregroundStyle(.tint)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Back to Disk")
            .accessibilityLabel("Back to Disk")

            Text(id.title)
                .fontWeight(.semibold)
                .lineLimit(1)
                .truncationMode(.tail)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            Text(Format.disk(total))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, isDocker ? 14 : 8)
    }

    private var controls: some View {
        HStack(alignment: .center) {
            selectAll
            Spacer(minLength: 8)
            sortMenu
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    /// Checked when every item is, mixed when some are.
    private var selectAll: some View {
        let selectable = items.filter { !$0.isOpen }
        let checkedCount = selectable.count(where: isChecked)
        // Two sources so the checkbox can show the mixed state: "any checked" and "all checked".
        // Setting both does the work once; the second finds nothing left to change.
        let sources = [
            Binding(get: { checkedCount > 0 }, set: { diskMonitor.setKept(!$0, selectable) }),
            Binding(get: { !selectable.isEmpty && checkedCount == selectable.count }, set: { diskMonitor.setKept(!$0, selectable) }),
        ]
        return Toggle(sources: sources, isOn: \.self) {
            Text("Select all (\(selectable.count))")
                .monospacedDigit()
        }
        .toggleStyle(.checkbox)
        .disabled(selectable.isEmpty)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sort) {
                ForEach(ItemSort.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Text("Sort: \(Text(sort.title))")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .foregroundStyle(.secondary)
        .help("Sort items")
    }

    // MARK: List

    private var list: some View {
        let rows = sortedItems
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { item in
                        DiskItemRow(
                            item: item,
                            checkbox: isDocker ? nil : Binding(
                                get: { isChecked(item) },
                                set: { diskMonitor.setKept(!$0, item) }
                            ),
                            isSelected: selected == item.id,
                            isFocused: listFocused,
                            preview: fileURL(item).map { url in { previewURL = url } },
                            reveal: fileURL(item).map { url in { reveal(url) } },
                            select: {
                                selected = item.id
                                listFocused = true
                            }
                        )
                        .id(item.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(height: min(CGFloat(rows.count) * DiskItemRow.height + 8, Self.maxListHeight))
            .focusable()
            .focused($listFocused)
            .focusEffectDisabled()
            .onKeyPress(.space) {
                guard let item = rows.first(where: { $0.id == selected }), let url = fileURL(item) else { return .ignored }
                previewURL = previewURL == url ? nil : url
                return .handled
            }
            .onKeyPress(.downArrow) { move(by: 1, in: rows, proxy: proxy) }
            .onKeyPress(.upArrow) { move(by: -1, in: rows, proxy: proxy) }
            .quickLookPreview($previewURL, in: rows.compactMap(fileURL))
        }
    }

    private func move(by offset: Int, in rows: [DiskItem], proxy: ScrollViewProxy) -> KeyPress.Result {
        guard !rows.isEmpty else { return .ignored }
        let index = rows.firstIndex { $0.id == selected }.map { $0 + offset } ?? (offset > 0 ? 0 : rows.count - 1)
        let next = rows[min(max(index, 0), rows.count - 1)]
        selected = next.id
        proxy.scrollTo(next.id)
        if previewURL != nil, let url = fileURL(next) { previewURL = url }
        return .handled
    }

    private func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            if isDocker {
                Button("Clean", action: cleanDocker)
                    .buttonStyle(.borderedProminent)
                    .disabled(isDockerWorking)
                    .help("Remove Docker's unused images and build cache")
            } else {
                let checked = checkedItems
                let permanently = id.removesPermanently(optionDown: OptionKey.shared.isDown)
                Button(id.removalTitle(permanently: permanently, count: checked.count, size: checked.reduce(0) { $0 + $1.size }),
                       action: removeChecked)
                    .buttonStyle(.borderedProminent)
                    .tint(permanently ? .red : nil)
                    .monospacedDigit()
                    .lineLimit(1)
                    .fixedSize()
                    .disabled(checked.isEmpty || diskMonitor.working.contains(id))
            }

            Spacer(minLength: 8)

            if id.removal == .trash {
                OptionDeleteHint()
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var isDockerWorking: Bool {
        if case .working = diskMonitor.docker { return true }
        return false
    }

    /// Removes the checked items, then goes back; the category's row shows the progress.
    private func removeChecked() {
        // Decided now, not when the title was drawn: it's what picks Trash over Delete.
        let permanently = id.removesPermanently(optionDown: OptionKey.shared.isDown)
        // The snapshot may be stale: drop what's been kept, opened or rescanned away since.
        let current = Set(diskMonitor.selection(in: id).map(\.id))
        let items = checkedItems.filter { current.contains($0.id) }
        let id = id
        if !items.isEmpty {
            Task { await diskMonitor.remove(items, from: id, permanently: permanently) }
        }
        close()
    }

    private func cleanDocker() {
        Task { await diskMonitor.cleanDocker() }
        close()
    }
}

/// How the items screen orders its rows.
private enum ItemSort: String, CaseIterable, Identifiable {
    case size, age

    var id: Self { self }

    var title: LocalizedStringKey {
        switch self {
        case .size: "Size"
        case .age: "Age"
        }
    }
}

/// One item: checkbox, name, "8 months · Open", size. Click highlights it, double-click reveals it in Finder.
private struct DiskItemRow: View {
    let item: DiskItem
    /// Nil for Docker, which is cleaned as a whole.
    let checkbox: Binding<Bool>?
    let isSelected: Bool
    let isFocused: Bool
    /// Nil when the item isn't a file (simulators, Docker).
    let preview: (() -> Void)?
    let reveal: (() -> Void)?
    let select: () -> Void

    static let height: CGFloat = 28

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isChecked: Bool { checkbox?.wrappedValue ?? true }

    /// "iOS 17.2 · 8 months · Open".
    private var caption: String? {
        var parts: [String] = []
        if let detail = item.detail { parts.append(detail) }
        if let lastUsed = item.lastUsed { parts.append(Format.age(since: lastUsed)) }
        if item.isOpen { parts.append(String(localized: "Open")) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 8) {
            if let checkbox {
                Toggle("", isOn: checkbox)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    .disabled(item.isOpen)
            }

            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isChecked ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))

            if let caption {
                // Gives way first, so a long path never pushes the size out of the row.
                Text("· \(caption)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
            }

            Spacer(minLength: 8)

            Text(Format.disk(item.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(background)
                .padding(.horizontal, 6)
        }
        .contentShape(Rectangle())
        .help(item.path ?? item.name)
        .onTapGesture(count: 2) { reveal?() }
        .simultaneousGesture(TapGesture().onEnded(select))
        .onHover { hovering in
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { isHovered = hovering }
        }
        .accessibilityRepresentation {
            if let checkbox {
                Toggle(isOn: checkbox) { Text(accessibilityLabel) }
                    .disabled(item.isOpen)
            } else {
                Text(accessibilityLabel)
            }
        }
        .accessibilityActions {
            if let preview { Button("Quick Look", action: preview) }
            if let reveal { Button("Show in Finder", action: reveal) }
        }
    }

    private var background: AnyShapeStyle {
        if isSelected { return AnyShapeStyle(Brand.indigo.opacity(isFocused ? 0.16 : 0.08)) }
        return AnyShapeStyle(.primary.opacity(isHovered ? 0.06 : 0))
    }

    /// "report.mov, 8 months, 1.2 GB".
    private var accessibilityLabel: String {
        [item.name, caption?.replacingOccurrences(of: " · ", with: ", "), Format.disk(item.size)]
            .compactMap { $0 }
            .joined(separator: ", ")
    }
}
