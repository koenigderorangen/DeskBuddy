import Combine
import Foundation
import UserNotifications

enum DeskBuddyNotification {
    static let automaticMovementCategory = "AUTOMATIC_MOVEMENT"
    static let stopAutomaticMovementAction = "STOP_AUTOMATIC_MOVEMENT"
}

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
    @Published private(set) var nextScheduleStart: Date?

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

    func refreshSchedule() {
        evaluate()
    }

#if DEBUG
    func sendTestNotification() {
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            let content = UNMutableNotificationContent()
            content.title = "DeskBuddy Test Notification"
            content.body = "Notifications are working in this development build."
            content.sound = .default
            try? await center.add(
                UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            )
        }
    }

    func triggerTestCountdown() {
        let settings = SettingsStore.shared
        let targetKind: PresetKind = currentPostureIsSitting() ? .standing : .sitting
        guard let target = settings.presets.first(where: { $0.resolvedKind == targetKind }) else { return }
        sendReminder(target: target, includesCountdown: true)
        startCountdown(to: target, seconds: settings.movementCountdownSeconds)
    }
#endif

    private func evaluate() {
        let settings = SettingsStore.shared
        guard settings.coachEnabled,
              settings.coachReminderEnabled || settings.automaticMovementEnabled else {
            nextReminder = nil
            nextScheduleStart = nil
            return
        }

        let now = Date()
        guard isInsideActiveSchedule(settings: settings, at: now) else {
            nextReminder = nil
            nextScheduleStart = nextActiveScheduleStart(settings: settings, after: now)
            return
        }
        nextScheduleStart = nil

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

        if settings.coachReminderEnabled || settings.automaticMovementEnabled {
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
            content.body = "DeskBuddy will move to \(target.name) shortly. Use Stop / Cancel to prevent it."
            content.categoryIdentifier = DeskBuddyNotification.automaticMovementCategory
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

    private func isInsideActiveSchedule(settings: SettingsStore, at date: Date) -> Bool {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let currentMinute = calendar.component(.hour, from: date) * 60
            + calendar.component(.minute, from: date)
        let startMinute = settings.activeStartHour * 60 + settings.activeStartMinute
        let endMinute = settings.activeEndHour * 60 + settings.activeEndMinute
        if startMinute == endMinute {
            return settings.activeWeekdays.contains(weekday)
        }
        if startMinute < endMinute {
            return settings.activeWeekdays.contains(weekday)
                && currentMinute >= startMinute
                && currentMinute < endMinute
        }
        if currentMinute >= startMinute {
            return settings.activeWeekdays.contains(weekday)
        }
        guard currentMinute < endMinute,
              let previousDay = calendar.date(byAdding: .day, value: -1, to: date) else { return false }
        return settings.activeWeekdays.contains(calendar.component(.weekday, from: previousDay))
    }

    private func nextActiveScheduleStart(settings: SettingsStore, after date: Date) -> Date? {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: date)
        for dayOffset in 0...7 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: startOfToday),
                  settings.activeWeekdays.contains(calendar.component(.weekday, from: day)),
                  let candidate = calendar.date(
                      bySettingHour: settings.activeStartHour,
                      minute: settings.activeStartMinute,
                      second: 0,
                      of: day
                  ),
                  candidate > date else { continue }
            return candidate
        }
        return nil
    }

    private func scheduleNextDate(from date: Date) {
        let sitting = currentPostureIsSitting()
        let settings = SettingsStore.shared
        let minutes = sitting ? settings.sittingIntervalMinutes : settings.standingIntervalMinutes
        nextReminder = date.addingTimeInterval(Double(minutes * 60))
    }
}
