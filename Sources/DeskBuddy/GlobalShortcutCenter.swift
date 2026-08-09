import Carbon
import Combine
import Foundation

@MainActor
final class GlobalShortcutCenter {
    static let shared = GlobalShortcutCenter()

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private var cancellables = Set<AnyCancellable>()
    private let signature: OSType = 0x4F44434B // ODCK

    private init() {
        installHandler()
        reload()
        Publishers.CombineLatest(
            SettingsStore.shared.$shortcuts,
            SettingsStore.shared.$disabledShortcutActions
        )
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.reload() }
            .store(in: &cancellables)
    }

    private func installHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        _ = eventTypes.withUnsafeMutableBufferPointer { types in
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, event, context in
                    guard let event, let context else { return OSStatus(eventNotHandledErr) }
                    var hotKeyID = EventHotKeyID()
                    let status = GetEventParameter(
                        event,
                        EventParamName(kEventParamDirectObject),
                        EventParamType(typeEventHotKeyID),
                        nil,
                        MemoryLayout<EventHotKeyID>.size,
                        nil,
                        &hotKeyID
                    )
                    guard status == noErr else { return status }
                    let pressed = GetEventKind(event) == UInt32(kEventHotKeyPressed)
                    let center = Unmanaged<GlobalShortcutCenter>.fromOpaque(context).takeUnretainedValue()
                    Task { @MainActor in center.handle(id: hotKeyID.id, pressed: pressed) }
                    return noErr
                },
                types.count,
                types.baseAddress,
                context,
                &eventHandler
            )
        }
    }

    func reload() {
        suspend()
        for action in ShortcutAction.allCases where SettingsStore.shared.shortcutIsEnabled(action) {
            let shortcut = SettingsStore.shared.shortcut(for: action)
            register(id: action.hotKeyID, keyCode: shortcut.keyCode, modifiers: shortcut.modifiers)
        }
    }

    func suspend() {
        for reference in hotKeyRefs where reference != nil {
            UnregisterEventHotKey(reference)
        }
        hotKeyRefs.removeAll()
    }

    private func register(id: UInt32, keyCode: UInt32, modifiers: UInt32) {
        var reference: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        if RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &reference
        ) == noErr {
            hotKeyRefs.append(reference)
        }
    }

    private func handle(id: UInt32, pressed: Bool) {
        guard SettingsStore.shared.shortcutsEnabled else { return }
        switch id {
        case 1:
            if pressed, let preset = SettingsStore.shared.presets.first {
                DeskController.shared.move(to: preset)
            }
        case 2:
            if pressed, SettingsStore.shared.presets.count > 1 {
                DeskController.shared.move(to: SettingsStore.shared.presets[1])
            }
        case 3:
            if pressed { DeskController.shared.stopMovement() }
        case 4:
            pressed ? DeskController.shared.startManual(.up) : DeskController.shared.stopMovement()
        case 5:
            pressed ? DeskController.shared.startManual(.down) : DeskController.shared.stopMovement()
        default:
            break
        }
    }
}
