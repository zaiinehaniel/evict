import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @Bindable var settings: AppSettings

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                Toggle("Show memory usage in menu bar", isOn: $settings.showMemoryInMenuBar)
            }

            Section {
                Picker("Default idle time", selection: $settings.defaultIdleMinutes) {
                    ForEach(IdleRule.presets, id: \.self) { minutes in
                        Text(Format.longDuration(minutes: minutes)).tag(minutes)
                    }
                }
                Toggle("Evict idle apps automatically", isOn: $settings.autoEvict)
                Toggle("Notify before evicting", isOn: $settings.notifyBeforeEvicting)
                    .disabled(!settings.autoEvict)
                Toggle("Only when memory is low", isOn: $settings.onlyUnderMemoryPressure)
                    .disabled(!settings.autoEvict)
                Toggle(isOn: $settings.stricterOnBattery) {
                    Text("Be stricter on battery")
                    Text("On battery or in Low Power Mode, apps count as idle after half the usual time.")
                }
            } header: {
                Text("Evicting")
            } footer: {
                Text("Evict never closes the app you're using, or apps playing audio, in a call, keeping the Mac awake or busy working. Apps always quit gracefully, like pressing ⌘Q.")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}
