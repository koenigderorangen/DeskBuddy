import AppIntents
import Foundation

private let englishLocale = Locale(identifier: "en")

struct PausePostureCoachFocusFilter: SetFocusFilterIntent {
    static let title = LocalizedStringResource("DeskBuddy Posture Coach", locale: englishLocale)
    static let description = IntentDescription(
        LocalizedStringResource(
            "Pauses automatic desk movement while this Focus is active.",
            locale: englishLocale
        )
    )

    @Parameter(
        title: LocalizedStringResource("Pause Automatic Movement", locale: englishLocale),
        default: false
    )
    var pauseAutomaticMovement: Bool

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: LocalizedStringResource("DeskBuddy Posture Coach", locale: englishLocale),
            subtitle: pauseAutomaticMovement
                ? LocalizedStringResource("Automatic movement paused", locale: englishLocale)
                : LocalizedStringResource("Automatic movement allowed", locale: englishLocale)
        )
    }

    func perform() async throws -> some IntentResult {
        await MainActor.run {
            SettingsStore.shared.setFocusPausesAutomaticMovement(pauseAutomaticMovement)
            PostureCoach.shared.refreshSchedule()
        }
        return .result()
    }
}

struct MoveDeskToSittingIntent: AppIntent {
    static let title = LocalizedStringResource("Move Desk to Sitting Height", locale: englishLocale)
    static let description = IntentDescription(
        LocalizedStringResource("Moves the connected desk to the first saved position.", locale: englishLocale)
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run { () -> String in
            guard let preset = SettingsStore.shared.presets.first else {
                return "No sitting position is saved."
            }
            guard DeskController.shared.state.isConnected else {
                return "The desk is not connected."
            }
            DeskController.shared.move(to: preset)
            return "The desk is moving to \(preset.name)."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct MoveDeskToStandingIntent: AppIntent {
    static let title = LocalizedStringResource("Move Desk to Standing Height", locale: englishLocale)
    static let description = IntentDescription(
        LocalizedStringResource("Moves the connected desk to the second saved position.", locale: englishLocale)
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run { () -> String in
            guard SettingsStore.shared.presets.count > 1 else {
                return "No standing position is saved."
            }
            guard DeskController.shared.state.isConnected else {
                return "The desk is not connected."
            }
            let preset = SettingsStore.shared.presets[1]
            DeskController.shared.move(to: preset)
            return "The desk is moving to \(preset.name)."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct MoveDeskToHeightIntent: AppIntent {
    static let title = LocalizedStringResource("Move Desk to Height", locale: englishLocale)
    static let description = IntentDescription(
        LocalizedStringResource("Moves the connected desk to a specified height.", locale: englishLocale)
    )

    @Parameter(
        title: LocalizedStringResource("Height in Centimeters", locale: englishLocale),
        inclusiveRange: (62, 127)
    )
    var height: Double

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let message = await MainActor.run { () -> String in
            guard DeskController.shared.state.isConnected else {
                return "The desk is not connected."
            }
            DeskController.shared.move(to: height)
            return "The desk is moving to \(String(format: "%.1f", height)) centimeters."
        }
        return .result(dialog: IntentDialog(stringLiteral: message))
    }
}

struct StopDeskIntent: AppIntent {
    static let title = LocalizedStringResource("Stop Desk", locale: englishLocale)
    static let description = IntentDescription(
        LocalizedStringResource("Stops any desk movement immediately.", locale: englishLocale)
    )

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { DeskController.shared.stopMovement() }
        return .result(
            dialog: IntentDialog(LocalizedStringResource("The desk has stopped.", locale: englishLocale))
        )
    }
}

struct GetDeskHeightIntent: AppIntent {
    static let title = LocalizedStringResource("Get Desk Height", locale: englishLocale)
    static let description = IntentDescription(
        LocalizedStringResource("Returns the current height of the connected desk.", locale: englishLocale)
    )

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let height = await MainActor.run { DeskController.shared.heightCm }
        guard let height else {
            return .result(
                value: -1,
                dialog: IntentDialog(
                    LocalizedStringResource("The desk height is unavailable.", locale: englishLocale)
                )
            )
        }
        return .result(
            value: height,
            dialog: IntentDialog(stringLiteral: "The desk is \(String(format: "%.1f", height)) centimeters high.")
        )
    }
}

struct OpenDeskShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MoveDeskToSittingIntent(),
            phrases: ["Sit with \(.applicationName)", "\(.applicationName) sitting height"],
            shortTitle: LocalizedStringResource("Sitting Height", locale: englishLocale),
            systemImageName: "chair"
        )
        AppShortcut(
            intent: MoveDeskToStandingIntent(),
            phrases: ["Stand with \(.applicationName)", "\(.applicationName) standing height"],
            shortTitle: LocalizedStringResource("Standing Height", locale: englishLocale),
            systemImageName: "figure.stand"
        )
        AppShortcut(
            intent: StopDeskIntent(),
            phrases: ["Stop the desk with \(.applicationName)"],
            shortTitle: LocalizedStringResource("Stop Desk", locale: englishLocale),
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: GetDeskHeightIntent(),
            phrases: ["Desk height with \(.applicationName)"],
            shortTitle: LocalizedStringResource("Desk Height", locale: englishLocale),
            systemImageName: "arrow.up.and.down"
        )
    }
}
