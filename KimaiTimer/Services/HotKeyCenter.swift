import AppKit
import Carbon.HIToolbox

/// Registers one system-wide keyboard shortcut. Uses the Carbon hot key API, which needs no
/// Accessibility permission and works inside the App Sandbox.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    var onPressed: (() -> Void)?
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    func register(_ shortcut: Shortcut?) {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
        guard let shortcut else { return }
        installHandlerIfNeeded()
        let identifier = EventHotKeyID(signature: OSType(0x4B54_4D52), id: 1) // "KTMR"
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode), Self.carbonModifiers(shortcut.modifiers), identifier,
            GetApplicationEventTarget(), 0, &reference)
        if status == noErr { hotKey = reference }
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, _ in
                Task { @MainActor in HotKeyCenter.shared.onPressed?() }
                return noErr
            },
            1, &eventType, nil, &handler)
    }

    private static func carbonModifiers(_ rawFlags: UInt) -> UInt32 {
        let flags = NSEvent.ModifierFlags(rawValue: rawFlags)
        var result = 0
        if flags.contains(.command) { result |= cmdKey }
        if flags.contains(.option) { result |= optionKey }
        if flags.contains(.control) { result |= controlKey }
        if flags.contains(.shift) { result |= shiftKey }
        return UInt32(result)
    }
}

extension Shortcut {
    /// Builds a shortcut from a key press, or `nil` if it lacks ⌘, ⌥ or ⌃ and would
    /// therefore swallow normal typing everywhere.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !flags.intersection([.command, .option, .control]).isEmpty else { return nil }
        var symbols = ""
        if flags.contains(.control) { symbols += "⌃" }
        if flags.contains(.option) { symbols += "⌥" }
        if flags.contains(.shift) { symbols += "⇧" }
        if flags.contains(.command) { symbols += "⌘" }
        self.init(
            keyCode: event.keyCode, modifiers: flags.rawValue,
            display: symbols + Self.keyName(for: event))
    }

    private static func keyName(for event: NSEvent) -> String {
        switch Int(event.keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        case kVK_F1: return "F1"
        case kVK_F2: return "F2"
        case kVK_F3: return "F3"
        case kVK_F4: return "F4"
        case kVK_F5: return "F5"
        case kVK_F6: return "F6"
        case kVK_F7: return "F7"
        case kVK_F8: return "F8"
        case kVK_F9: return "F9"
        case kVK_F10: return "F10"
        case kVK_F11: return "F11"
        case kVK_F12: return "F12"
        default:
            return event.charactersIgnoringModifiers?.uppercased() ?? "?"
        }
    }
}
