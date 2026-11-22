#if DEBUG
import AppKit
import KimaiKit
import SwiftUI

/// Development-only launch mode: `KimaiTimer --snapshot <folder>` renders the main views with
/// sample data into PNG files and quits, so the UI can be reviewed without clicking through
/// the app. `scripts/snapshots.sh` builds an unsandboxed debug copy for this, because a
/// sandboxed app cannot write to a folder of your choice.
enum DebugLaunch {
    static func handle() -> Bool {
        let arguments = CommandLine.arguments
        if arguments.contains("--smoke-demo") {
            Task {
                var test = SmokeTest()
                exit(await test.run())
            }
            return true
        }
        guard let index = arguments.firstIndex(of: "--snapshot"), arguments.indices.contains(index + 1) else {
            return false
        }
        let directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
        Task {
            await SnapshotRunner(directory: directory).run()
            exit(0)
        }
        return true
    }
}

private struct SnapshotRunner {
    let directory: URL

    func run() async {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let idle = PreviewData.model(running: false)
        let running = PreviewData.model(running: true)
        let offline = PreviewData.model(running: true, problem: .offline)
        let fresh = AppModel(
            preferences: Preferences(defaults: UserDefaults(suiteName: "app.kimaitimer.mac.preview-empty") ?? .standard),
            secrets: MemorySecretStore(), cache: CatalogCache(fileName: "preview-empty.json"))
        let editEntry = EditorRequest(mode: .edit(PreviewData.entries[0]))

        await render("01-main-idle", MainWindowView().environment(idle), size: CGSize(width: 900, height: 640), dark: false)
        await render("02-main-running-dark", MainWindowView().environment(running), size: CGSize(width: 900, height: 640), dark: true)
        await render("03-main-offline", MainWindowView().environment(offline), size: CGSize(width: 760, height: 520), dark: false)
        await render("04-menu-running", MenuBarPanel().environment(running), size: nil, dark: false)
        await render("05-menu-idle-dark", MenuBarPanel().environment(idle), size: nil, dark: true)
        await render("06-editor", EntryEditorView(request: editEntry).environment(idle), size: nil, dark: false)
        await render(
            "07-picker", BookingPickerList(booking: .constant(Booking(projectID: 20, activityID: 100))) {}
                .environment(idle),
            size: CGSize(width: 440, height: 380), dark: false)
        await render("08-welcome", MainWindowView().environment(fresh), size: CGSize(width: 760, height: 480), dark: false)
        await render("09-settings-general", GeneralSettingsView().environment(idle), size: CGSize(width: 520, height: 470), dark: false)
        print("SNAPSHOTS \(directory.path)")
    }

    private func render(_ name: String, _ view: some View, size: CGSize?, dark: Bool) async {
        let hosting = NSHostingView(rootView: AnyView(
            view.background(Color(nsColor: .windowBackgroundColor))
                .environment(\.colorScheme, dark ? .dark : .light)))
        let contentSize = size ?? hosting.fittingSize
        let window = NSWindow(
            contentRect: NSRect(origin: NSPoint(x: -20000, y: -20000), size: contentSize),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = hosting
        // Key window of the active app, so controls are drawn in their active colours.
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(700))

        let bounds = hosting.bounds
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: bounds) else { return }
        hosting.cacheDisplay(in: bounds, to: bitmap)
        if let data = bitmap.representation(using: .png, properties: [:]) {
            try? data.write(to: directory.appendingPathComponent("\(name).png"))
        }
        window.orderOut(nil)
    }
}
#endif
