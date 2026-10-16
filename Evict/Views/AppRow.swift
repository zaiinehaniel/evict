import SwiftUI

struct AppRow: View {
    let entry: AppEntry
    let monitor: AppMonitor

    static let height: CGFloat = 40

    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var memoryText: String { entry.memory.map(Format.memory) ?? "—" }
    private var statusText: String {
        if entry.isQuitting { return String(localized: "Quitting…") }
        let base = entry.isActive ? String(localized: "Active") : Format.idleLabel(entry.idle, pastLimit: entry.isIdle)
        if let busy = entry.busyReason { return "\(base) · \(busy.label)" }
        if let cpu = entry.notableBackgroundCPU {
            return "\(base) · \(String(localized: "\(Int((cpu * 100).rounded()))% CPU"))"
        }
        return base
    }
    private var protectTitle: LocalizedStringKey { entry.isProtected ? "Unprotect" : "Protect" }

    private var confirmation: PendingConfirmation? {
        switch monitor.pendingConfirmation {
        case .quit(entry.id), .forceQuit(entry.id): monitor.pendingConfirmation
        default: nil
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: entry.app.icon)
                .resizable()
                .interpolation(.high)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(entry.app.name)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if entry.isProtected {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(statusText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(entry.isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            }

            Spacer(minLength: 8)

            if let confirmation {
                confirmButtons(confirmation)
                    .transition(.opacity)
            } else if entry.isQuitting {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
                Text(memoryText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 60, alignment: .trailing)
            } else {
                if isHovered {
                    quickActions
                        .transition(.opacity)
                } else if let evictsIn = entry.evictsIn {
                    Text("in \(Format.duration(evictsIn))")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary, in: Capsule())
                        .help("Evicts in \(Format.duration(evictsIn))")
                        .transition(.opacity)
                }
                Text(memoryText)
                    .monospacedDigit()
                    .foregroundStyle(entry.memory == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                    .frame(minWidth: 60, alignment: .trailing)
            }
        }
        .opacity(entry.isQuitting ? 0.6 : 1)
        .animation(animation, value: entry.isQuitting)
        .padding(.horizontal, 14)
        .frame(height: Self.height)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.primary.opacity(isHovered || confirmation != nil ? 0.06 : 0))
                .padding(.horizontal, 6)
        }
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(animation) { isHovered = hovering }
        }
        .contextMenu { menu }
        .accessibilityElement(children: confirmation == nil ? .ignore : .contain)
        .accessibilityLabel(entry.app.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityAction(named: "Quit") { ask(.quit(entry.id)) }
        .accessibilityAction(named: protectTitle) { monitor.toggleProtection(entry) }
    }

    private var animation: Animation? { reduceMotion ? nil : .easeOut(duration: 0.15) }

    private func ask(_ confirmation: PendingConfirmation) {
        withAnimation(animation) { monitor.pendingConfirmation = confirmation }
    }

    private var quickActions: some View {
        HStack(spacing: 0) {
            Button(protectTitle, systemImage: entry.isProtected ? "lock.fill" : "lock.open") {
                monitor.toggleProtection(entry)
            }
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
            .help(protectTitle)

            Button("Quit \(entry.app.name)", systemImage: "xmark.circle") { ask(.quit(entry.id)) }
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
                .help("Quit \(entry.app.name)")
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
    }

    private func confirmButtons(_ confirmation: PendingConfirmation) -> some View {
        let isForce = confirmation == .forceQuit(entry.id)
        return HStack(spacing: 6) {
            Button("Cancel") {
                withAnimation(animation) { monitor.pendingConfirmation = nil }
            }
            .keyboardShortcut(.cancelAction)

            Button(isForce ? LocalizedStringKey("Force Quit") : LocalizedStringKey("Quit")) {
                isForce ? monitor.forceQuit(entry) : monitor.quit(entry)
            }
            .keyboardShortcut(.defaultAction)
            .tint(isForce ? .red : nil)
            .buttonStyle(.borderedProminent)
        }
        .controlSize(.small)
    }

    @ViewBuilder
    private var menu: some View {
        Button("Quit") { ask(.quit(entry.id)) }
        Button("Force Quit…") { ask(.forceQuit(entry.id)) }
        Divider()
        Button(protectTitle) { monitor.toggleProtection(entry) }
        Picker("Set Idle Time", selection: Bindable(monitor.settings)[ruleForApp: entry.app.key]) {
            Text("Default (\(Format.longDuration(minutes: monitor.settings.defaultIdleMinutes)))").tag(IdleRule.automatic)
            ForEach(IdleRule.presets, id: \.self) { minutes in
                Text(Format.longDuration(minutes: minutes)).tag(IdleRule.minutes(minutes))
            }
            Divider()
            Text("Never").tag(IdleRule.never)
        }
        Divider()
        Button("Show in Finder") { monitor.showInFinder(entry) }
            .disabled(entry.app.bundleURL == nil)
    }

    private var accessibilityValue: String {
        var parts = [statusText]
        if entry.memory != nil { parts.append(memoryText) }
        if let evictsIn = entry.evictsIn { parts.append(String(localized: "Evicts in \(Format.duration(evictsIn))")) }
        if entry.isProtected { parts.append(String(localized: "Protected")) }
        return parts.joined(separator: ", ")
    }
}
