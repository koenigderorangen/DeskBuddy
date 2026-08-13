import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()

    @Published var presets: [DeskPreset] { didSet { save(presets, key: Keys.presets) } }
    @Published var savedDesks: [SavedDesk] { didSet { save(savedDesks, key: Keys.savedDesks) } }
    @Published var lastDeskID: UUID? { didSet { defaults.set(lastDeskID?.uuidString, forKey: Keys.lastDeskID) } }
    @Published var useInches: Bool { didSet { defaults.set(useInches, forKey: Keys.useInches) } }
    @Published var menuBarPresentation: MenuBarPresentation { didSet { save(menuBarPresentation, key: Keys.menuBarPresentation) } }
    @Published var heightPrecision: HeightPrecision { didSet { save(heightPrecision, key: Keys.heightPrecision) } }
    @Published var theme: DeskBuddyTheme { didSet { save(theme, key: Keys.theme) } }
    @Published var autoReconnect: Bool { didSet { defaults.set(autoReconnect, forKey: Keys.autoReconnect) } }
    @Published var shortcutsEnabled: Bool { didSet { defaults.set(shortcutsEnabled, forKey: Keys.shortcuts) } }
    @Published var coachEnabled: Bool { didSet { defaults.set(coachEnabled, forKey: Keys.coachEnabled) } }
    @Published var coachReminderEnabled: Bool { didSet { defaults.set(coachReminderEnabled, forKey: Keys.coachReminderEnabled) } }
    @Published var automaticMovementEnabled: Bool { didSet { defaults.set(automaticMovementEnabled, forKey: Keys.automaticMovementEnabled) } }
    @Published var pauseAutomaticMovementDuringMeetings: Bool {
        didSet { defaults.set(pauseAutomaticMovementDuringMeetings, forKey: Keys.pauseAutomaticMovementDuringMeetings) }
    }
    @Published private(set) var focusPausesAutomaticMovement: Bool
    @Published var sittingIntervalMinutes: Int { didSet { defaults.set(sittingIntervalMinutes, forKey: Keys.sittingInterval) } }
    @Published var standingIntervalMinutes: Int { didSet { defaults.set(standingIntervalMinutes, forKey: Keys.standingInterval) } }
    @Published var activeStartHour: Int { didSet { defaults.set(activeStartHour, forKey: Keys.activeStartHour) } }
    @Published var activeStartMinute: Int { didSet { defaults.set(activeStartMinute, forKey: Keys.activeStartMinute) } }
    @Published var activeEndHour: Int { didSet { defaults.set(activeEndHour, forKey: Keys.activeEndHour) } }
    @Published var activeEndMinute: Int { didSet { defaults.set(activeEndMinute, forKey: Keys.activeEndMinute) } }
    @Published var activeWeekdays: Set<Int> { didSet { save(activeWeekdays, key: Keys.activeWeekdays) } }
    @Published var movementCountdownSeconds: Int { didSet { defaults.set(movementCountdownSeconds, forKey: Keys.countdown) } }
    @Published var paddleGesturesEnabled: Bool { didSet { defaults.set(paddleGesturesEnabled, forKey: Keys.doubleTap) } }
    @Published var paddleGestureContinuationDelay: Double {
        didSet { defaults.set(paddleGestureContinuationDelay, forKey: Keys.paddleGestureContinuationDelay) }
    }
    @Published var paddleGestureRules: [PaddleGestureRule] { didSet { save(paddleGestureRules, key: Keys.paddleGestureRules) } }
    @Published var shortcuts: [String: KeyboardShortcut] { didSet { save(shortcuts, key: Keys.shortcutsConfig) } }
    @Published var disabledShortcutActions: Set<String> { didSet { save(disabledShortcutActions, key: Keys.disabledShortcuts) } }
    @Published var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.onboarding) } }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let presets = "presets"
        static let savedDesks = "savedDesks"
        static let lastDeskID = "lastDeskID"
        static let useInches = "useInches"
        static let menuBarPresentation = "menuBarPresentation"
        static let heightPrecision = "heightPrecision"
        static let theme = "theme"
        static let autoReconnect = "autoReconnect"
        static let shortcuts = "shortcutsEnabled"
        static let coachEnabled = "coachEnabled"
        static let coachReminderEnabled = "coachReminderEnabled"
        static let automaticMovementEnabled = "automaticMovementEnabled"
        static let pauseAutomaticMovementDuringMeetings = "pauseAutomaticMovementDuringMeetings"
        static let focusPausesAutomaticMovement = "focusPausesAutomaticMovement"
        static let sittingInterval = "sittingIntervalMinutes"
        static let standingInterval = "standingIntervalMinutes"
        static let activeStartHour = "activeStartHour"
        static let activeStartMinute = "activeStartMinute"
        static let activeEndHour = "activeEndHour"
        static let activeEndMinute = "activeEndMinute"
        static let activeWeekdays = "activeWeekdays"
        static let countdown = "movementCountdownSeconds"
        static let doubleTap = "doubleTapEnabled"
        static let paddleGestureContinuationDelay = "paddleGestureContinuationDelay"
        static let paddleGestureRules = "paddleGestureRules"
        static let shortcutsConfig = "shortcutsConfig"
        static let disabledShortcuts = "disabledShortcuts"
        static let onboarding = "hasCompletedOnboarding"
    }

    private init() {
        var loadedPresets = Self.load([DeskPreset].self, key: Keys.presets) ?? DeskPreset.defaults
        for required in DeskPreset.defaults where !loadedPresets.contains(where: { $0.kind == required.kind }) {
            loadedPresets.append(required)
        }
        presets = loadedPresets
        savedDesks = Self.load([SavedDesk].self, key: Keys.savedDesks) ?? []
        lastDeskID = defaults.string(forKey: Keys.lastDeskID).flatMap(UUID.init(uuidString:))
        useInches = defaults.bool(forKey: Keys.useInches)
        menuBarPresentation = Self.load(MenuBarPresentation.self, key: Keys.menuBarPresentation) ?? .symbolAndValue
        heightPrecision = Self.load(HeightPrecision.self, key: Keys.heightPrecision) ?? .tenth
        theme = Self.load(DeskBuddyTheme.self, key: Keys.theme) ?? .system
        autoReconnect = defaults.object(forKey: Keys.autoReconnect) as? Bool ?? true
        shortcutsEnabled = defaults.object(forKey: Keys.shortcuts) as? Bool ?? true
        coachEnabled = defaults.bool(forKey: Keys.coachEnabled)
        coachReminderEnabled = defaults.object(forKey: Keys.coachReminderEnabled) as? Bool ?? true
        automaticMovementEnabled = defaults.bool(forKey: Keys.automaticMovementEnabled)
        pauseAutomaticMovementDuringMeetings = defaults.bool(forKey: Keys.pauseAutomaticMovementDuringMeetings)
        focusPausesAutomaticMovement = defaults.bool(forKey: Keys.focusPausesAutomaticMovement)
        sittingIntervalMinutes = defaults.object(forKey: Keys.sittingInterval) as? Int ?? 45
        standingIntervalMinutes = defaults.object(forKey: Keys.standingInterval) as? Int ?? 20
        activeStartHour = defaults.object(forKey: Keys.activeStartHour) as? Int ?? 9
        activeStartMinute = defaults.object(forKey: Keys.activeStartMinute) as? Int ?? 0
        activeEndHour = defaults.object(forKey: Keys.activeEndHour) as? Int ?? 18
        activeEndMinute = defaults.object(forKey: Keys.activeEndMinute) as? Int ?? 0
        activeWeekdays = Self.load(Set<Int>.self, key: Keys.activeWeekdays) ?? Set(2...6)
        movementCountdownSeconds = defaults.object(forKey: Keys.countdown) as? Int ?? 15
        paddleGesturesEnabled = defaults.bool(forKey: Keys.doubleTap)
        let storedContinuationDelay = defaults.object(forKey: Keys.paddleGestureContinuationDelay) as? Double ?? 0.4
        paddleGestureContinuationDelay = min(max(storedContinuationDelay, 0.1), 4)
        let sittingPresetID = loadedPresets.first(where: { $0.kind == .sitting })!.id
        let standingPresetID = loadedPresets.first(where: { $0.kind == .standing })!.id
        var gestureRules = Self.load([PaddleGestureRule].self, key: Keys.paddleGestureRules) ?? [
            PaddleGestureRule(directions: [.down, .down], presetID: sittingPresetID),
            PaddleGestureRule(directions: [.up, .up], presetID: standingPresetID)
        ]
        gestureRules = gestureRules.filter { rule in
            rule.directions.count >= 2 && loadedPresets.contains(where: { $0.id == rule.presetID })
        }
        paddleGestureRules = gestureRules
        shortcuts = Self.load([String: KeyboardShortcut].self, key: Keys.shortcutsConfig) ?? [:]
        disabledShortcutActions = Self.load(Set<String>.self, key: Keys.disabledShortcuts) ?? []
        hasCompletedOnboarding = defaults.bool(forKey: Keys.onboarding)
    }

    func formattedHeight(_ centimeters: Double) -> String {
        let digits = heightPrecision == .whole ? 0 : 1
        if useInches {
            return String(format: "%.*f in", digits, centimeters / 2.54)
        }
        return String(format: "%.*f cm", digits, centimeters)
    }

    func setFocusPausesAutomaticMovement(_ paused: Bool) {
        focusPausesAutomaticMovement = paused
        defaults.set(paused, forKey: Keys.focusPausesAutomaticMovement)
    }

    func shortcut(for action: ShortcutAction) -> KeyboardShortcut {
        shortcuts[action.rawValue] ?? action.defaultShortcut
    }

    func setShortcut(_ shortcut: KeyboardShortcut, for action: ShortcutAction) {
        shortcuts[action.rawValue] = shortcut
        disabledShortcutActions.remove(action.rawValue)
    }

    func shortcutIsEnabled(_ action: ShortcutAction) -> Bool {
        !disabledShortcutActions.contains(action.rawValue)
    }

    func disableShortcut(for action: ShortcutAction) {
        disabledShortcutActions.insert(action.rawValue)
    }

    func resetShortcut(for action: ShortcutAction) {
        shortcuts[action.rawValue] = action.defaultShortcut
        disabledShortcutActions.remove(action.rawValue)
    }

    func preset(for rule: PaddleGestureRule) -> DeskPreset? {
        presets.first(where: { $0.id == rule.presetID })
    }

    func addPaddleGestureRule(directions: [ManualDirection], presetID: UUID) {
        guard directions.count >= 2,
              !paddleGestureRules.contains(where: { $0.directions == directions }) else { return }
        paddleGestureRules.append(PaddleGestureRule(directions: directions, presetID: presetID))
    }

    func updatePaddleGestureRule(_ rule: PaddleGestureRule) {
        guard rule.directions.count >= 2,
              !paddleGestureRules.contains(where: { $0.id != rule.id && $0.directions == rule.directions }),
              let index = paddleGestureRules.firstIndex(where: { $0.id == rule.id }) else { return }
        paddleGestureRules[index] = rule
    }

    func deletePaddleGestureRule(_ rule: PaddleGestureRule) {
        paddleGestureRules.removeAll { $0.id == rule.id }
    }

    func updatePreset(_ preset: DeskPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        var safe = preset
        safe.heightCm = min(max(safe.heightCm, DeskProtocol.minimumHeightCm), DeskProtocol.maximumHeightCm)
        presets[index] = safe
    }

    func deletePreset(_ preset: DeskPreset) {
        guard preset.kind == .custom else { return }
        presets.removeAll { $0.id == preset.id }
        paddleGestureRules.removeAll { $0.presetID == preset.id }
    }

    func movePreset(_ preset: DeskPreset, offset: Int) {
        guard let source = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        let destination = min(max(source + offset, 0), presets.count - 1)
        guard source != destination else { return }
        let value = presets.remove(at: source)
        presets.insert(value, at: destination)
    }

    private func save<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        defaults.set(data, forKey: key)
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
