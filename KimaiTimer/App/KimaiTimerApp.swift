import KimaiKit
import SwiftUI

@main
struct KimaiTimerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let model = AppModel.shared

    var body: some Scene {
        Window("Kimai Timer", id: "main") {
            MainWindowView()
                .environment(model)
        }
        .defaultSize(width: 900, height: 640)
        .commands {
            AppCommands(model: model)
        }

        MenuBarExtra {
            MenuBarPanel()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(model)
        }
    }
}

struct AppCommands: Commands {
    let model: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button(L("New Entry…")) {
                model.showMainWindow(focusDescription: false)
                model.newEntry()
            }
            .keyboardShortcut("n")
        }
        CommandMenu(L("Timer")) {
            Button(L("Start or Stop Timer")) {
                model.toggleTimer()
            }
            .keyboardShortcut(.return, modifiers: .command)
            Divider()
            Button(L("Refresh")) {
                Task { await model.refresh() }
            }
            .keyboardShortcut("r")
            Button(L("Reload Projects and Activities")) {
                Task { await model.refresh(reloadCatalog: true) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            Divider()
            Button(L("Open Kimai in Browser")) {
                model.openKimaiInBrowser()
            }
            .keyboardShortcut("k", modifiers: [.command, .shift])
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let idleMonitor = IdleMonitor()

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if DebugLaunch.handle() { return }
        #endif
        let model = AppModel.shared
        Task { await model.bootstrap() }
        idleMonitor.start(model: model)
        HotKeyCenter.shared.onPressed = { model.showMainWindow() }
        HotKeyCenter.shared.register(model.preferences.shortcut)
    }

    /// Closing the window must not stop tracking: the app lives on in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { AppModel.shared.showMainWindow() }
        return true
    }
}
