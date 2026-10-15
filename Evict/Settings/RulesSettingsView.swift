import SwiftUI
import UniformTypeIdentifiers

/// Apps with their own idle time, or "Never" (protected).
struct RulesSettingsView: View {
    @Bindable var settings: AppSettings
    let monitor: AppMonitor

    @State private var selection: Set<String> = []

    private var apps: [AppReference] {
        settings.ruledAppKeys.map(AppReference.init)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Running apps that don't have a rule yet, for the Add menu.
    private var runningWithoutRule: [RunningAppInfo] {
        monitor.apps
            .filter { app in app.key.map { settings.rule(forKey: $0) == .automatic } ?? false }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Give an app its own idle time, or choose Never to protect it. Other apps use the default (\(Format.longDuration(minutes: settings.defaultIdleMinutes))).")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(apps) { app in
                        RuleRow(app: app, rule: rule(for: app.key))
                    }
                    .onDelete { offsets in
                        offsets.map { apps[$0].key }.forEach(settings.removeRule(forKey:))
                    }
                }
                .listStyle(.bordered(alternatesRowBackgrounds: true))
                .overlay {
                    if apps.isEmpty {
                        Text("No rules yet")
                            .foregroundStyle(.secondary)
                    }
                }
                .onDeleteCommand(perform: removeSelected)

                HStack(spacing: 0) {
                    addMenu
                    Divider().frame(height: 16)
                    Button(action: removeSelected) {
                        Image(systemName: "minus").frame(width: 24, height: 20)
                    }
                    .disabled(selection.isEmpty)
                    .help("Remove Rule")
                    .accessibilityLabel("Remove Rule")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }
        }
        .padding(20)
        .frame(width: 480, height: 360)
    }

    private var addMenu: some View {
        Menu {
            if !runningWithoutRule.isEmpty {
                Section("Open Apps") {
                    ForEach(runningWithoutRule) { app in
                        Button {
                            add(app.key)
                        } label: {
                            Label { Text(app.name) } icon: { Image(nsImage: app.icon) }
                        }
                    }
                }
            }
            Button("Choose App…", action: chooseApp)
        } label: {
            Image(systemName: "plus").frame(width: 24, height: 20)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Add App")
        .accessibilityLabel("Add App")
    }

    private func rule(for key: String) -> Binding<IdleRule> {
        Binding(
            get: { settings.rule(forKey: key) },
            set: { settings.setRule($0, forKey: key) }
        )
    }

    /// New rules start as "Never": protecting an app is the most common reason to add one.
    private func add(_ key: String?) {
        guard let key else { return }
        settings.setRule(.never, forKey: key)
        selection = [key]
    }

    private func removeSelected() {
        selection.forEach(settings.removeRule(forKey:))
        selection = []
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = String(localized: "Add")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        add(AppReference.key(for: url))
    }
}

private struct RuleRow: View {
    let app: AppReference
    @Binding var rule: IdleRule

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 20, height: 20)
            Text(app.name)
                .lineLimit(1)
            Spacer()
            Picker("Idle time for \(app.name)", selection: $rule) {
                ForEach(IdleRule.presets, id: \.self) { minutes in
                    Text(Format.longDuration(minutes: minutes)).tag(IdleRule.minutes(minutes))
                }
                Divider()
                Text("Never").tag(IdleRule.never)
            }
            .labelsHidden()
            .fixedSize()
        }
        .padding(.vertical, 2)
        .tag(app.key)
    }
}
