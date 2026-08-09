import Combine
import Foundation
import UserNotifications

@MainActor
final class PostureCoach: ObservableObject {
    struct PendingMovement: Identifiable, Equatable {
        let id = UUID()
        let preset: DeskPreset
    }

    static let shared = PostureCoach()

    @Published private(set) var pendingMovement: PendingMovement?
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var nextReminder: Date?

    private var evaluationTimer: Timer?
    private var countdownTask: Task<Void, Never>?
    private let lastReminderKey = "coachLastReminder"

    private init() {
        evaluationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        evaluate()
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func cancelPendingMovement() {
        countdownTask?.cancel()
        countdownTask = nil
        pendingMovement = nil
        remainingSeconds = 0
    }

    func resetSchedule() {
        cancelPendingMovement()
        UserDefaults.standard.set(Date(), forKey: lastReminderKey)
        evaluate()
    }

    private func evaluate() {
        let settings = SettingsStore.shared
        guard settings.coachEnabled,
              settings.coachReminderEnabled || settings.automaticMovementEnabled,
              isInsideActiveSchedule(settings: settings) else {
            nextReminder = nil
            return
        }

        let now = Date()
        guard let lastReminder = UserDefaults.standard.object(forKey: lastReminderKey) as? Date else {
            UserDefaults.standard.set(now, forKey: lastReminderKey)
            scheduleNextDate(from: now)
            return
        }

        let sitting = currentPostureIsSitting()
        let intervalMinutes = sitting ? settings.sittingIntervalMinutes : settings.standingIntervalMinutes
        let due = lastReminder.addingTimeInterval(Double(intervalMinutes * 60))
        nextReminder = due
        guard now >= due, pendingMovement == nil else { return }

        let targetKind: PresetKind = sitting ? .standing : .sitting
        guard let target = settings.presets.first(where: { $0.resolvedKind == targetKind }) else { return }

        if settings.coachReminderEnabled {
            sendReminder(target: target, includesCountdown: settings.automaticMovementEnabled)
        }
        if settings.automaticMovementEnabled, DeskController.shared.state.isConnected {
            startCountdown(to: target, seconds: settings.movementCountdownSeconds)
        }

        UserDefaults.standard.set(now, forKey: lastReminderKey)
        scheduleNextDate(from: now)
    }

    private func startCountdown(to preset: DeskPreset, seconds: Int) {
        cancelPendingMovement()
        pendingMovement = PendingMovement(preset: preset)
        remainingSeconds = max(seconds, 5)

        countdownTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.remainingSeconds -= 1
                if self.remainingSeconds <= 0 {
                    self.countdownTask = nil
                    let target = self.pendingMovement?.preset
                    self.pendingMovement = nil
                    if let target, DeskController.shared.state.isConnected {
                        DeskController.shared.move(to: target)
                    }
                    return
                }
            }
        }
    }

    private func sendReminder(target: DeskPreset, includesCountdown: Bool) {
        let content = UNMutableNotificationContent()
        content.title = "Time to Change Position"
        if includesCountdown {
            content.body = "DeskBuddy will move to \(target.name) shortly. Open the app to cancel."
        } else {
            content.body = "How about \(target.name.lowercased()) now?"
        }
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        )
    }

    private func currentPostureIsSitting() -> Bool {
        let settings = SettingsStore.shared
        guard let height = DeskController.shared.heightCm,
              let sitting = settings.presets.first(where: { $0.resolvedKind == .sitting }),
              let standing = settings.presets.first(where: { $0.resolvedKind == .standing }) else {
            return true
        }
        return height < (sitting.heightCm + standing.heightCm) / 2
    }

    private func isInsideActiveSchedule(settings: SettingsStore) -> Bool {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        return settings.activeWeekdays.contains(weekday)
            && hour >= settings.activeStartHour
            && hour < settings.activeEndHour
    }

    private func scheduleNextDate(from date: Date) {
        let sitting = currentPostureIsSitting()
        let settings = SettingsStore.shared
        let minutes = sitting ? settings.sittingIntervalMinutes : settings.standingIntervalMinutes
        nextReminder = date.addingTimeInterval(Double(minutes * 60))
    }
}
