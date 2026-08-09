import AppKit
import Carbon
import SwiftUI

struct KeyboardShortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    var display: String {
        modifierSymbols + KeyboardShortcut.keyName(for: keyCode)
    }

    private var modifierSymbols: String {
        var result = ""
        if modifiers & UInt32(controlKey) != 0 { result += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { result += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { result += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { result += "⌘" }
        return result
    }

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        return result
    }

    private static func keyName(for keyCode: UInt32) -> String {
        if let name = names[keyCode] { return name }
        return "Key \(keyCode)"
    }

    private static let names: [UInt32: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7",
        27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 50: "`",
        36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑"
    ]
}

enum ShortcutAction: String, CaseIterable, Identifiable {
    case firstPreset
    case secondPreset
    case moveUp
    case moveDown
    case stop

    var id: String { rawValue }

    var hotKeyID: UInt32 {
        switch self {
        case .firstPreset: 1
        case .secondPreset: 2
        case .stop: 3
        case .moveUp: 4
        case .moveDown: 5
        }
    }

    var title: String {
        switch self {
        case .firstPreset: "First saved position"
        case .secondPreset: "Second saved position"
        case .moveUp: "Move up (hold)"
        case .moveDown: "Move down (hold)"
        case .stop: "Stop immediately"
        }
    }

    var symbol: String {
        switch self {
        case .firstPreset: "1.circle"
        case .secondPreset: "2.circle"
        case .moveUp: "arrow.up"
        case .moveDown: "arrow.down"
        case .stop: "stop.fill"
        }
    }

    var defaultShortcut: KeyboardShortcut {
        let controlOption = UInt32(controlKey | optionKey)
        switch self {
        case .firstPreset: return KeyboardShortcut(keyCode: 18, modifiers: controlOption)
        case .secondPreset: return KeyboardShortcut(keyCode: 19, modifiers: controlOption)
        case .moveUp: return KeyboardShortcut(keyCode: 126, modifiers: controlOption)
        case .moveDown: return KeyboardShortcut(keyCode: 125, modifiers: controlOption)
        case .stop: return KeyboardShortcut(keyCode: 29, modifiers: controlOption)
        }
    }
}

struct ShortcutRecorder: View {
    let action: ShortcutAction
    @ObservedObject private var settings = SettingsStore.shared
    @State private var recording = false
    @State private var escapeHolding = false
    @State private var monitor: Any?
    @State private var escapeTask: Task<Void, Never>?

    var body: some View {
        Button {
            recording ? stop() : start()
        } label: {
            Text(displayText)
                .font(.system(.body, design: .rounded).weight(.medium))
                .frame(minWidth: 72)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .glassEffect(.clear, in: Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(recording ? Color.accentColor : settings.shortcutIsEnabled(action) ? Color.primary : .secondary)
        .help("Click and press a shortcut. Hold Escape for one second to disable it.")
        .contextMenu {
            Button("Reset to Default") { settings.resetShortcut(for: action) }
        }
        .onDisappear { stop() }
    }

    private var displayText: String {
        if escapeHolding { return "Keep holding Esc…" }
        if recording { return "Press shortcut…" }
        if !settings.shortcutIsEnabled(action) { return "Off" }
        return settings.shortcut(for: action).display
    }

    private func start() {
        recording = true
        GlobalShortcutCenter.shared.suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { event in
            MainActor.assumeIsolated { handle(event) }
            return nil
        }
    }

    private func handle(_ event: NSEvent) {
        if event.keyCode == 53 {
            handleEscape(event)
            return
        }
        guard event.type == .keyDown, !event.isARepeat else { return }
        let modifiers = KeyboardShortcut.carbonModifiers(from: event.modifierFlags)
        guard modifiers != 0 else {
            NSSound.beep()
            return
        }
        settings.setShortcut(
            KeyboardShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers),
            for: action
        )
        stop()
    }

    private func handleEscape(_ event: NSEvent) {
        if event.type == .keyUp {
            escapeTask?.cancel()
            escapeTask = nil
            stop()
            return
        }
        guard !event.isARepeat, escapeTask == nil else { return }
        escapeHolding = true
        escapeTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            settings.disableShortcut(for: action)
            escapeTask = nil
            stop()
        }
    }

    private func stop() {
        recording = false
        escapeHolding = false
        escapeTask?.cancel()
        escapeTask = nil
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        GlobalShortcutCenter.shared.reload()
    }
}
