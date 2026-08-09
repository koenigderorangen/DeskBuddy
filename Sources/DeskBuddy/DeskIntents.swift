import AppIntents
import Foundation

struct MoveDeskToSittingIntent: AppIntent {
    static let title: LocalizedStringResource = "Move Desk to Sitting Height"
    static let description = IntentDescription("Moves the connected desk to the first saved position.")

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
    static let title: LocalizedStringResource = "Move Desk to Standing Height"
    static let description = IntentDescription("Moves the connected desk to the second saved position.")

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
    static let title: LocalizedStringResource = "Move Desk to Height"
    static let description = IntentDescription("Moves the connected desk to a height between 62 and 127 centimeters.")

    @Parameter(title: "Height in Centimeters", inclusiveRange: (62, 127))
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
    static let title: LocalizedStringResource = "Stop Desk"
    static let description = IntentDescription("Stops any desk movement immediately.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run { DeskController.shared.stopMovement() }
        return .result(dialog: "The desk has stopped.")
    }
}

struct GetDeskHeightIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Desk Height"
    static let description = IntentDescription("Returns the current height of the connected desk.")

    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let height = await MainActor.run { DeskController.shared.heightCm }
        guard let height else {
            return .result(value: -1, dialog: "The desk height is unavailable.")
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
            shortTitle: "Sitting Height",
            systemImageName: "chair"
        )
        AppShortcut(
            intent: MoveDeskToStandingIntent(),
            phrases: ["Stand with \(.applicationName)", "\(.applicationName) standing height"],
            shortTitle: "Standing Height",
            systemImageName: "figure.stand"
        )
        AppShortcut(
            intent: StopDeskIntent(),
            phrases: ["Stop the desk with \(.applicationName)"],
            shortTitle: "Stop Desk",
            systemImageName: "stop.fill"
        )
        AppShortcut(
            intent: GetDeskHeightIntent(),
            phrases: ["Desk height with \(.applicationName)"],
            shortTitle: "Desk Height",
            systemImageName: "arrow.up.and.down"
        )
    }
}
