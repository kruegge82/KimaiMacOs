import KimaiKit
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettingsView()
                .tabItem { Label(L("General"), systemImage: "gearshape") }
            ConnectionForm()
                .tabItem { Label(L("Connection"), systemImage: "network") }
        }
        .frame(width: 520, height: 470)
    }
}

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var launchAtLoginFailed = false

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section {
                Toggle(L("Open at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        guard enabled != LaunchAtLogin.isEnabled else { return }
                        if !LaunchAtLogin.setEnabled(enabled) {
                            launchAtLoginFailed = true
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
                Toggle(L("Show seconds in the menu bar"), isOn: $preferences.showSecondsInMenuBar)
                    .onChange(of: preferences.showSecondsInMenuBar) { model.updateMenuBarText() }
            } footer: {
                if launchAtLoginFailed {
                    Text(L("macOS did not allow this. Move Kimai Timer to the Applications folder and try again."))
                        .foregroundStyle(.red)
                }
            }

            Section {
                Toggle(L("Ask about idle time while a timer runs"), isOn: $preferences.idleDetectionEnabled)
                Picker(L("Counts as idle after"), selection: $preferences.idleMinutes) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { minutes in
                        Text(L("%d minutes", minutes)).tag(minutes)
                    }
                }
                .disabled(!preferences.idleDetectionEnabled)
            } footer: {
                Text(L("When you come back, you decide whether the time away stays on the timer. Nothing is removed automatically."))
            }

            Section {
                LabeledContent(L("Show Kimai Timer from anywhere")) {
                    ShortcutRecorder(shortcut: $preferences.shortcut)
                }
                .onChange(of: preferences.shortcut) { _, shortcut in
                    HotKeyCenter.shared.register(shortcut)
                }
            }

            Section {
                LabeledContent(L("Projects and activities")) {
                    Button(L("Reload")) {
                        Task { await model.refresh(reloadCatalog: true) }
                    }
                    .disabled(!model.isConfigured || model.isRefreshing)
                }
            } footer: {
                if !model.catalog.isEmpty {
                    Text(L(
                        "%d projects and %d activities, loaded %@.",
                        model.catalog.projects.count, model.catalog.activities.count,
                        model.catalog.fetchedAt.formatted(date: .abbreviated, time: .shortened)))
                }
            }
        }
        .formStyle(.grouped)
    }
}
