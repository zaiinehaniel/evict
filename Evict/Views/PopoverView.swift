import SwiftUI

struct PopoverView: View {
    let monitor: AppMonitor
    var openSettings: () -> Void = {}

    @AppStorage("sortOrder") private var sortOrder: SortOrder = .worthClosing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let width: CGFloat = 360
    private static let maxListHeight: CGFloat = 420

    var body: some View {
        let entries = sortOrder.sorted(monitor.entries)
        let evictable = entries.filter(\.isEvictable)
        let reclaimable = evictable.compactMap(\.memory).reduce(0, +)

        VStack(spacing: 0) {
            header(evictable: evictable, reclaimable: reclaimable)
            Divider()
            list(entries)
            if !monitor.background.isEmpty {
                Divider()
                BackgroundSection(groups: monitor.background)
            }
            if !monitor.recentlyEvicted.isEmpty {
                Divider()
                RecentlyEvictedSection(items: Array(monitor.recentlyEvicted.prefix(3)), now: monitor.now, reopen: monitor.reopen)
            }
            Divider()
            footer(evictable: evictable, reclaimable: reclaimable)
        }
        .frame(width: Self.width)
    }

    // MARK: - Header

    private func header(evictable: [AppEntry], reclaimable: UInt64) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            MemoryGauge(system: monitor.system, isSavingEnergy: monitor.isSavingEnergy)

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
        HStack(spacing: 10) {
            FreeSlotMark(size: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text("Nothing overstaying.")
                    .font(.callout.weight(.medium))
                Text("Your Mac has room to breathe.")
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

    private var sortMenu: some View {
        Menu {
            Picker("Sort by", selection: $sortOrder) {
                ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: "arrow.up.arrow.down")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Sort apps")
        .accessibilityLabel("Sort apps")
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

                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .keyboardShortcut(",")
                .help("Settings")
                .accessibilityLabel("Settings")

                Button { NSApp.terminate(nil) } label: {
                    Image(systemName: "power")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .keyboardShortcut("q")
                .help("Quit Evict")
                .accessibilityLabel("Quit Evict")
            }
        }
        .frame(height: 28)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
