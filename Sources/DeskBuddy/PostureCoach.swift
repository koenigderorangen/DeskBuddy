import Combine
import Foundation
import UserNotifications

enum DeskBuddyNotification {
    static let automaticMovementCategory = "AUTOMATIC_MOVEMENT"
    static let stopAutomaticMovementAction = "STOP_AUTOMATIC_MOVEMENT"
    static let postureReminderCategory = "POSTURE_REMINDER"
    static let moveToReminderPresetAction = "MOVE_TO_REMINDER_PRESET"
    static let presetIDKey = "presetID"
    static let postureCoachRequest = "POSTURE_COACH_REMINDER"
}

@MainActor
final class PostureCoach: ObservableObject {
    enum PauseReason: Equatable {
        case meeting
        case focus
    }

    struct PendingMovement: Identifiable, Equatable {
        let id = UUID()
        let preset: DeskPreset
    }

    static let shared = PostureCoach()

    @Published private(set) var pendingMovement: PendingMovement?
    @Published private(set) var remainingSeconds = 0
    @Published private(set) var nextReminder: Date?
    @Published private(set) var nextScheduleStart: Date?
    @Published private(set) var currentPosture: PresetKind = .sitting
    @Published private(set) var nextPosture: PresetKind = .standing
    @Published private(set) var pauseReason: PauseReason?

    private var evaluationTimer: Timer?
    private var countdownTask: Task<Void, Never>?
    private var positionObservation: AnyCancellable?
    private var connectionObservation: AnyCancellable?
    private var trackedPosture: PresetKind?
    private var wasDeskConnected = false
    private var isSuspendedForDisconnectedDesk = false
    private var lastDiagnosticState: String?
    private let lastReminderKey = "coachLastReminder"
    private let trackedPostureKey = "coachTrackedPosture"

    private init() {
        if let rawPosture = UserDefaults.standard.string(forKey: trackedPostureKey),
           let posture = PresetKind(rawValue: rawPosture),
           posture == .sitting || posture == .standing {
            trackedPosture = posture
            currentPosture = posture
            nextPosture = posture == .sitting ? .standing : .sitting
            record("Restored \(posture.rawValue) posture and interval anchor")
        }
        positionObservation = DeskController.shared.$speedCmPerSecond
            .sink { [weak self] speed in
                self?.deskPositionDidChange(height: DeskController.shared.heightCm, speed: speed)
            }
        connectionObservation = DeskController.shared.$state
            .map(\.isConnected)
            .removeDuplicates()
            .sink { [weak self] isConnected in
                self?.deskConnectionDidChange(isConnected: isConnected)
            }
        evaluationTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        evaluate()
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                if let error {
                    self.record("Notification permission failed: \(error.localizedDescription)")
                } else {
                    self.record("Notification permission \(granted ? "granted" : "denied")")
                }
            }
        }
    }

    func cancelPendingMovement() {
        let cancelledPreset = pendingMovement?.preset.name
        countdownTask?.cancel()
        countdownTask = nil
        pendingMovement = nil
        remainingSeconds = 0
        if let cancelledPreset {
            record("Cancelled countdown to \(cancelledPreset)")
        }
    }

    func resetSchedule() {
        cancelPendingMovement()
        removeCoachNotifications()
        UserDefaults.standard.set(Date(), forKey: lastReminderKey)
        record("Schedule reset from current time")
        evaluate()
    }

    func refreshSchedule() {
        evaluate()
    }

#if DEBUG
    func sendTestNotification() {
        guard DeskController.shared.state.isConnected else {
            record("Test reminder skipped because no desk was connected")
            return
        }
        let settings = SettingsStore.shared
        let targetKind: PresetKind = currentPostureIsSitting() ? .standing : .sitting
        guard let target = settings.presets.first(where: { $0.kind == targetKind }) else { return }
        Task {
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            sendReminder(target: target, includesCountdown: false)
        }
    }

    func triggerTestCountdown() {
        guard DeskController.shared.state.isConnected else {
            record("Test countdown skipped because no desk was connected")
            return
        }
        let settings = SettingsStore.shared
        let targetKind: PresetKind = currentPostureIsSitting() ? .standing : .sitting
        guard let target = settings.presets.first(where: { $0.kind == targetKind }) else { return }
        sendReminder(target: target, includesCountdown: true)
        startCountdown(to: target, seconds: settings.movementCountdownSeconds)
    }
#endif

    private func evaluate() {
        let settings = SettingsStore.shared
        guard DeskController.shared.state.isConnected else {
            suspendForDisconnectedDesk()
            return
        }
        guard settings.coachEnabled,
              settings.coachReminderEnabled || settings.automaticMovementEnabled else {
            cancelPendingMovement()
            nextReminder = nil
            nextScheduleStart = nil
            pauseReason = nil
            recordState("Inactive")
            return
        }

        let now = Date()
        let sitting = currentPostureIsSitting()
        currentPosture = sitting ? .sitting : .standing
        nextPosture = sitting ? .standing : .sitting

        guard isInsideActiveSchedule(settings: settings, at: now) else {
            cancelPendingMovement()
            nextReminder = nil
            nextScheduleStart = nextActiveScheduleStart(settings: settings, after: now)
            pauseReason = nil
            recordState("Outside schedule; next start \(formatted(nextScheduleStart))")
            return
        }
        nextScheduleStart = nil

        guard let lastReminder = UserDefaults.standard.object(forKey: lastReminderKey) as? Date else {
            UserDefaults.standard.set(now, forKey: lastReminderKey)
            scheduleNextDate(from: now)
            recordState("Initialized \(currentPosture.rawValue) interval; due \(formatted(nextReminder))")
            return
        }

        let intervalMinutes = sitting ? settings.sittingIntervalMinutes : settings.standingIntervalMinutes
        let due = lastReminder.addingTimeInterval(Double(intervalMinutes * 60))
        nextReminder = due

        if let reason = automaticMovementPauseReason(settings: settings) {
            cancelPendingMovement()
            pauseReason = reason
            recordState("Automatic movement paused by \(reason == .meeting ? "meeting activity" : "Focus")")
            return
        }
        pauseReason = nil

        guard now >= due, pendingMovement == nil else {
            if pendingMovement == nil {
                recordState("\(currentPosture.rawValue) interval; due \(formatted(due))")
            }
            return
        }

        let targetKind: PresetKind = sitting ? .standing : .sitting
        guard let target = settings.presets.first(where: { $0.kind == targetKind }) else {
            record("Interval due but no \(targetKind.rawValue) preset was available")
            return
        }
        record("Interval due; target is \(target.name) at \(String(format: "%.1f", target.heightCm)) cm")

        if settings.coachReminderEnabled || settings.automaticMovementEnabled {
            sendReminder(target: target, includesCountdown: settings.automaticMovementEnabled)
        }
        if settings.automaticMovementEnabled, DeskController.shared.state.isConnected {
            startCountdown(to: target, seconds: settings.movementCountdownSeconds)
        }

        UserDefaults.standard.set(now, forKey: lastReminderKey)
        scheduleNextDate(from: now)
    }

    private func deskConnectionDidChange(isConnected: Bool) {
        guard isConnected != wasDeskConnected else { return }
        wasDeskConnected = isConnected
        if isConnected {
            isSuspendedForDisconnectedDesk = false
            UserDefaults.standard.set(Date(), forKey: lastReminderKey)
            record("Desk connected; started a fresh posture interval")
            evaluate()
        } else {
            suspendForDisconnectedDesk()
        }
    }

    private func suspendForDisconnectedDesk() {
        guard !isSuspendedForDisconnectedDesk else { return }
        isSuspendedForDisconnectedDesk = true
        cancelPendingMovement()
        removeCoachNotifications()
        nextReminder = nil
        nextScheduleStart = nil
        pauseReason = nil
        recordState("Inactive because no desk is connected")
    }

    private func startCountdown(to preset: DeskPreset, seconds: Int) {
        cancelPendingMovement()
        pendingMovement = PendingMovement(preset: preset)
        remainingSeconds = max(seconds, 5)
        record("Started \(remainingSeconds)-second countdown to \(preset.name)")

        countdownTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                self.remainingSeconds -= 1
                if self.remainingSeconds <= 0 {
                    self.countdownTask = nil
                    let target = self.pendingMovement?.preset
                    self.pendingMovement = nil
                    let settings = SettingsStore.shared
                    if let reason = self.automaticMovementPauseReason(settings: settings) {
                        self.pauseReason = reason
                        self.remainingSeconds = 0
                        self.record("Countdown ended but movement was paused by \(reason == .meeting ? "meeting activity" : "Focus")")
                    } else if let target, DeskController.shared.state.isConnected {
                        self.record("Countdown completed; moving to \(target.name)")
                        DeskController.shared.move(to: target)
                    } else {
                        self.record("Countdown completed but desk was not connected")
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
            content.categoryIdentifier = DeskBuddyNotification.postureReminderCategory
            content.userInfo[DeskBuddyNotification.presetIDKey] = target.id.uuidString
        }
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: DeskBuddyNotification.postureCoachRequest,
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.record("Notification failed for \(target.name): \(error.localizedDescription)")
                } else {
                    self?.record("Notification delivered for \(target.name) (\(includesCountdown ? "automatic" : "reminder"))")
                }
            }
        }
    }

    private func deskPositionDidChange(height: Double?, speed: Double) {
        guard abs(speed) < 0.05,
              let height,
              let posture = postureAtPreset(height: height),
              posture != trackedPosture else { return }

        trackedPosture = posture
        currentPosture = posture
        nextPosture = posture == .sitting ? .standing : .sitting
        UserDefaults.standard.set(posture.rawValue, forKey: trackedPostureKey)
        UserDefaults.standard.set(Date(), forKey: lastReminderKey)
        record("Reached \(posture.rawValue) preset at \(String(format: "%.1f", height)) cm; started new interval")
        cancelPendingMovement()
        removeCoachNotifications()
        evaluate()
    }

    private func postureAtPreset(height: Double) -> PresetKind? {
        let candidates = SettingsStore.shared.presets.filter {
            $0.kind == .sitting || $0.kind == .standing
        }
        return candidates
            .map { (posture: $0.kind, distance: abs($0.heightCm - height)) }
            .filter { $0.distance <= 0.5 }
            .min(by: { $0.distance < $1.distance })?
            .posture
    }

    private func removeCoachNotifications() {
        let center = UNUserNotificationCenter.current()
        let identifiers = [DeskBuddyNotification.postureCoachRequest]
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        center.removeDeliveredNotifications(withIdentifiers: identifiers)
        record("Cleared previous interval notification")
    }

    private func recordState(_ state: String) {
        guard state != lastDiagnosticState else { return }
        lastDiagnosticState = state
        record(state)
    }

    private func record(_ message: String) {
        DeskController.shared.recordDiagnosticEvent("Coach: \(message)")
    }

    private func formatted(_ date: Date?) -> String {
        date.map { ISO8601DateFormatter().string(from: $0) } ?? "unavailable"
    }

    private func currentPostureIsSitting() -> Bool {
        if let trackedPosture {
            return trackedPosture == .sitting
        }
        let settings = SettingsStore.shared
        guard let height = DeskController.shared.heightCm,
              let sitting = settings.presets.first(where: { $0.kind == .sitting }),
              let standing = settings.presets.first(where: { $0.kind == .standing }) else {
            return true
        }
        return height < (sitting.heightCm + standing.heightCm) / 2
    }

    private func automaticMovementPauseReason(settings: SettingsStore) -> PauseReason? {
        guard settings.automaticMovementEnabled else { return nil }
        if settings.focusPausesAutomaticMovement {
            return .focus
        }
        if settings.pauseAutomaticMovementDuringMeetings,
           MeetingActivityMonitor.currentState().isActive {
            return .meeting
        }
        return nil
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
