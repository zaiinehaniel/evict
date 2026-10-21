import SwiftUI

/// The popover's two views of the Mac: open apps (Memory) and reclaimable storage (Disk).
enum PopoverTab: String, CaseIterable {
    case memory, disk

    static let storageKey = "popoverTab"

    /// The remembered tab, for code outside the view.
    static var current: PopoverTab {
        UserDefaults.standard.string(forKey: storageKey).flatMap(PopoverTab.init(rawValue:)) ?? .memory
    }

    var title: LocalizedStringKey {
        switch self {
        case .memory: "Memory"
        case .disk: "Disk"
        }
    }
}

struct PopoverView: View {
    let monitor: AppMonitor
    let diskMonitor: DiskMonitor
    var openSettings: () -> Void = {}

    @AppStorage("sortOrder") private var sortOrder: SortOrder = .worthClosing
    @AppStorage(PopoverTab.storageKey) private var tab: PopoverTab = .memory
    /// The Disk category opened from its row, shown in place of the whole Disk tab. Forgotten when the popover closes.
    @State private var openCategory: DiskCategoryID?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let width: CGFloat = 360
    private static let maxListHeight: CGFloat = 420

    var body: some View {
        Group {
            switch tab {
            case .memory: memoryTab
            case .disk: diskTab
            }
        }
        .frame(width: Self.width)
        .onChange(of: tab) { _, tab in
            monitor.pendingConfirmation = nil
            diskMonitor.pendingConfirmation = nil
            openCategory = nil
            // Opening the popover on the Disk tab scans from `StatusItemController`; switching to it scans here.
            if tab == .disk { diskMonitor.scan() } else { diskMonitor.cancelScan() }
        }
        // The popover's content outlives each opening; the next one starts on the overview.
        .onReceive(NotificationCenter.default.publisher(for: NSPopover.didCloseNotification)) { _ in
            openCategory = nil
        }
    }

    private var tabPicker: some View {
        Picker("View", selection: $tab) {
            ForEach(PopoverTab.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(maxWidth: .infinity)
    }

    // MARK: - Memory

    private var memoryTab: some View {
        let entries = sortOrder.sorted(monitor.entries)
        let evictable = entries.filter(\.isEvictable)
        let reclaimable = evictable.compactMap(\.memory).reduce(0, +)

        return VStack(spacing: 0) {
            header(evictable: evictable, reclaimable: reclaimable)
            Divider()
            list(entries)
            if !monitor.background.isEmpty {
                Divider()
                BackgroundSection(groups: monitor.background, monitor: monitor)
            }
            if !monitor.recentlyEvicted.isEmpty {
                Divider()
                RecentlyEvictedSection(items: Array(monitor.recentlyEvicted.prefix(3)), now: monitor.now, reopen: monitor.reopen)
            }
            Divider()
            footer(evictable: evictable, reclaimable: reclaimable)
        }
    }

    // MARK: - Header

    private func header(evictable: [AppEntry], reclaimable: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MemoryGauge(system: monitor.system, isSavingEnergy: monitor.isSavingEnergy)
            tabPicker

            HStack(alignment: .center) {
                if evictable.isEmpty {
                    emptyState
                } else {
                    Text("\(evictable.count) idle apps holding \(Format.memory(reclaimable))")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                sortMenu
            }
            .help("Default idle time: \(Format.longDuration(minutes: monitor.settings.defaultIdleMinutes))")
        }
        .padding(14)
    }

    private var emptyState: some View {
        EmptyStateCard(title: "Nothing overstaying.", message: "Your Mac has room to breathe.")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Sort apps", systemImage: "arrow.up.arrow.down")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort apps")
        .accessibilityValue(Text(sortOrder.title))
    }

    // MARK: - List

    @ViewBuilder
    private func list(_ entries: [AppEntry]) -> some View {
        if entries.isEmpty {
            Text("No apps open")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(entries) { entry in
                        AppRow(entry: entry, monitor: monitor)
                            .transition(.opacity)
                    }
                }
                .padding(.vertical, 4)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: entries.map(\.id))
            }
            .frame(height: min(CGFloat(entries.count) * AppRow.height + 8, Self.maxListHeight))
        }
    }

    // MARK: - Footer

    private var animation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.15) }

    private func footer(evictable: [AppEntry], reclaimable: UInt64) -> some View {
        HStack(spacing: 10) {
            if monitor.pendingConfirmation == .evictIdle, !evictable.isEmpty {
                Text("Quit \(evictable.count) idle apps?")
                    .font(.callout)
                Spacer()
                Button("Cancel") {
                    withAnimation(animation) { monitor.pendingConfirmation = nil }
                }
                .keyboardShortcut(.cancelAction)
                Button("Quit All") { monitor.evictIdleApps() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Evict idle apps") {
                    withAnimation(animation) { monitor.pendingConfirmation = .evictIdle }
                }
                .buttonStyle(.borderedProminent)
                .disabled(evictable.isEmpty)
                .help(evictable.isEmpty ? "No app is past its idle time yet" : "Quit apps past their idle time")

                if reclaimable > 0 {
                    Text("frees ~\(Format.memory(reclaimable))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                appButtons
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var appButtons: some View {
        HStack(spacing: 10) {
            Button("Settings", systemImage: "gearshape", action: openSettings)
                .keyboardShortcut(",")
                .help("Settings")

            Button("Quit Evict", systemImage: "power") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
                .help("Quit Evict")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

    // MARK: - Disk

    /// Pushes a category's items in from the trailing edge, or fades under Reduce Motion.
    private var pushAnimation: Animation { reduceMotion ? .easeOut(duration: 0.15) : .easeInOut(duration: 0.2) }

    private var diskTab: some View {
        ZStack {
            if let id = openCategory {
                // A category emptied by a background scan keeps its screen: it works on its own snapshot.
                DiskCategoryDetail(category: diskMonitor.category(id) ?? DiskCategory(id: id, items: [], total: 0),
                                   diskMonitor: diskMonitor) {
                    withAnimation(pushAnimation) { openCategory = nil }
                }
                .id(id)
                .transition(reduceMotion ? .opacity : .move(edge: .trailing))
            } else {
                VStack(spacing: 0) {
                    diskHeader
                    Divider()
                    DiskOverview(diskMonitor: diskMonitor) { id in
                        diskMonitor.pendingConfirmation = nil
                        withAnimation(pushAnimation) { openCategory = id }
                    }
                    Divider()
                    diskFooter
                }
                .transition(reduceMotion ? .opacity : .move(edge: .leading))
            }
        }
        .clipped()
    }

    private var diskHeader: some View {
        let reclaimable = diskMonitor.reclaimable(nil)
        return VStack(alignment: .leading, spacing: 12) {
            DiskGauge(volume: diskMonitor.volume)
            tabPicker

            HStack(alignment: .center) {
                if reclaimable > 0 {
                    Text("\(Format.disk(reclaimable)) can be cleared")
                        .font(.callout)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                if diskMonitor.isScanning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.mini)
                        Text("Scanning…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }
            }
            .frame(minHeight: 16)
            .animation(animation, value: diskMonitor.isScanning)
        }
        .padding(14)
    }

    private var diskFooter: some View {
        let clearable = diskMonitor.clearableAppJunk
        let isClearing = DiskCategoryID.allCases.contains { $0.group == .appJunk && diskMonitor.working.contains($0) }

        return HStack(spacing: 10) {
            if diskMonitor.pendingConfirmation == .clearAppJunk, clearable > 0 {
                Text("Delete \(Format.disk(clearable)) of app junk?")
                    .font(.callout)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Button("Cancel") {
                    withAnimation(animation) { diskMonitor.pendingConfirmation = nil }
                }
                .keyboardShortcut(.cancelAction)
                Button("Delete") {
                    Task { await diskMonitor.clearAppJunk() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .keyboardShortcut(.defaultAction)
            } else {
                Button("Clear app junk") {
                    withAnimation(animation) { diskMonitor.pendingConfirmation = .clearAppJunk }
                }
                .buttonStyle(.borderedProminent)
                .disabled(clearable == 0 || isClearing)
                .help(clearable == 0 ? "No app junk to clear" : "Delete Xcode data, simulators, package caches and app caches. Docker and your files aren't touched.")

                if clearable > 0 {
                    Text("frees ~\(Format.disk(clearable))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                appButtons
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

/// "Nothing overstaying." — the calm card shown when a tab has nothing to act on.
struct EmptyStateCard: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey

    var body: some View {
        HStack(spacing: 10) {
            FreeSlotMark(size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.callout.weight(.medium))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.indigo.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
