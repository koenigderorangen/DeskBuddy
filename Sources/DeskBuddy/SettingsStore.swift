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
    @Published var sittingIntervalMinutes: Int { didSet { defaults.set(sittingIntervalMinutes, forKey: Keys.sittingInterval) } }
    @Published var standingIntervalMinutes: Int { didSet { defaults.set(standingIntervalMinutes, forKey: Keys.standingInterval) } }
    @Published var activeStartHour: Int { didSet { defaults.set(activeStartHour, forKey: Keys.activeStartHour) } }
    @Published var activeEndHour: Int { didSet { defaults.set(activeEndHour, forKey: Keys.activeEndHour) } }
    @Published var activeWeekdays: Set<Int> { didSet { save(activeWeekdays, key: Keys.activeWeekdays) } }
    @Published var movementCountdownSeconds: Int { didSet { defaults.set(movementCountdownSeconds, forKey: Keys.countdown) } }
    @Published var doubleTapEnabled: Bool { didSet { defaults.set(doubleTapEnabled, forKey: Keys.doubleTap) } }

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
        static let sittingInterval = "sittingIntervalMinutes"
        static let standingInterval = "standingIntervalMinutes"
        static let activeStartHour = "activeStartHour"
        static let activeEndHour = "activeEndHour"
        static let activeWeekdays = "activeWeekdays"
        static let countdown = "movementCountdownSeconds"
        static let doubleTap = "doubleTapEnabled"
        static let englishPresetNamesMigrated = "englishPresetNamesMigrated"
    }

    private init() {
        var loadedPresets = Self.load([DeskPreset].self, key: Keys.presets) ?? DeskPreset.defaults
        if !defaults.bool(forKey: Keys.englishPresetNamesMigrated) {
            for index in loadedPresets.indices {
                if loadedPresets[index].resolvedKind == .sitting
                    || (loadedPresets[index].kind == nil && loadedPresets[index].symbol == "chair") {
                    loadedPresets[index].name = "Sit"
                    loadedPresets[index].kind = .sitting
                } else if loadedPresets[index].resolvedKind == .standing
                    || (loadedPresets[index].kind == nil && loadedPresets[index].symbol == "figure.stand") {
                    loadedPresets[index].name = "Stand"
                    loadedPresets[index].kind = .standing
                }
            }
            if let data = try? JSONEncoder().encode(loadedPresets) {
                defaults.set(data, forKey: Keys.presets)
            }
            defaults.set(true, forKey: Keys.englishPresetNamesMigrated)
        }
        for required in DeskPreset.defaults where !loadedPresets.contains(where: { $0.resolvedKind == required.resolvedKind }) {
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
        sittingIntervalMinutes = defaults.object(forKey: Keys.sittingInterval) as? Int ?? 45
        standingIntervalMinutes = defaults.object(forKey: Keys.standingInterval) as? Int ?? 20
        activeStartHour = defaults.object(forKey: Keys.activeStartHour) as? Int ?? 9
        activeEndHour = defaults.object(forKey: Keys.activeEndHour) as? Int ?? 18
        activeWeekdays = Self.load(Set<Int>.self, key: Keys.activeWeekdays) ?? Set(2...6)
        movementCountdownSeconds = defaults.object(forKey: Keys.countdown) as? Int ?? 15
        doubleTapEnabled = defaults.bool(forKey: Keys.doubleTap)
    }

    func formattedHeight(_ centimeters: Double) -> String {
        let digits = heightPrecision == .whole ? 0 : 1
        if useInches {
            return String(format: "%.*f in", digits, centimeters / 2.54)
        }
        return String(format: "%.*f cm", digits, centimeters)
    }

    func updatePreset(_ preset: DeskPreset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }) else { return }
        var safe = preset
        safe.heightCm = min(max(safe.heightCm, DeskProtocol.minimumHeightCm), DeskProtocol.maximumHeightCm)
        presets[index] = safe
    }

    func deletePreset(_ preset: DeskPreset) {
        guard preset.resolvedKind == .custom else { return }
        presets.removeAll { $0.id == preset.id }
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
