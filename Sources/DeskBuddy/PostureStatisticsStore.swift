import Combine
import Foundation

enum StatisticsPosture: String, Codable, CaseIterable, Identifiable {
    case sitting
    case standing
    case other

    var id: Self { self }

    var title: String {
        switch self {
        case .sitting: "Sit"
        case .standing: "Stand"
        case .other: "Other"
        }
    }
}

struct PostureStatisticsSession: Codable, Identifiable, Equatable {
    let id: UUID
    let connectionID: UUID
    let deskID: UUID
    let deskName: String
    let posture: StatisticsPosture
    let startedAt: Date
    var endedAt: Date
}

@MainActor
final class PostureStatisticsStore: ObservableObject {
    static let shared = PostureStatisticsStore()

    @Published private(set) var sessions: [PostureStatisticsSession]

    private let controller = DeskController.shared
    private let settings = SettingsStore.shared
    private var connectionObservation: AnyCancellable?
    private var positionObservation: AnyCancellable?
    private var heartbeatTimer: Timer?
    private var otherDwellTask: Task<Void, Never>?
    private var pendingOtherHeight: Double?
    private var activeSessionID: UUID?
    private var activeConnectionID: UUID?
    private var activeDeskID: UUID?
    private var activePosture: StatisticsPosture?
    private var isPaused = false

    private init() {
        sessions = Self.loadSessions()

        connectionObservation = controller.$state
            .map(\.isConnected)
            .removeDuplicates()
            .sink { [weak self] isConnected in
                self?.connectionDidChange(isConnected: isConnected)
            }
        positionObservation = controller.$speedCmPerSecond
            .sink { [weak self] speed in
                self?.positionDidChange(height: self?.controller.heightCm, speed: speed)
            }

        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updateActiveSessionEnd() }
        }
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
    }

    func pauseTracking() {
        isPaused = true
        cancelOtherDwell()
        closeActiveSession()
    }

    func resumeTracking() {
        guard isPaused else { return }
        isPaused = false
        if controller.state.isConnected {
            startConnection()
            positionDidChange(height: controller.heightCm, speed: controller.speedCmPerSecond)
        }
    }

    func stopTracking() {
        cancelOtherDwell()
        closeActiveSession()
    }

    func reset(deskID: UUID?) {
        let shouldRestart = activeDeskID != nil && (deskID == nil || activeDeskID == deskID)
        let restartPosture = shouldRestart ? activePosture : nil
        let restartDeskID = shouldRestart ? activeDeskID : nil
        let restartConnectionID = shouldRestart ? activeConnectionID : nil

        if shouldRestart {
            closeActiveSession()
        }
        if let deskID {
            sessions.removeAll { $0.deskID == deskID }
        } else {
            sessions.removeAll()
        }

        if let restartPosture, let restartDeskID, let restartConnectionID {
            activeDeskID = restartDeskID
            activeConnectionID = restartConnectionID
            beginSession(posture: restartPosture, at: Date())
        } else {
            saveSessions()
        }
    }

    private func connectionDidChange(isConnected: Bool) {
        if isConnected, !isPaused {
            startConnection()
            positionDidChange(height: controller.heightCm, speed: controller.speedCmPerSecond)
        } else {
            cancelOtherDwell()
            closeActiveSession()
            activeConnectionID = nil
            activeDeskID = nil
        }
    }

    private func startConnection() {
        guard let deskID = controller.connectedDeskID else { return }
        if activeDeskID != deskID || activeConnectionID == nil {
            closeActiveSession()
            activeDeskID = deskID
            activeConnectionID = UUID()
            activePosture = nil
        }
    }

    private func positionDidChange(height: Double?, speed: Double) {
        guard !isPaused,
              controller.state.isConnected,
              activeDeskID != nil,
              let height else { return }

        guard abs(speed) < 0.05 else {
            cancelOtherDwell()
            return
        }

        if let posture = presetPosture(at: height) {
            cancelOtherDwell()
            transition(to: posture)
        } else if activePosture == .other {
            cancelOtherDwell()
        } else {
            scheduleOtherDwell(at: height)
        }
    }

    private func presetPosture(at height: Double) -> StatisticsPosture? {
        let candidates = settings.presets.compactMap { preset -> (StatisticsPosture, Double)? in
            let posture: StatisticsPosture
            switch preset.kind {
            case .sitting: posture = .sitting
            case .standing: posture = .standing
            case .custom: return nil
            }
            return (posture, abs(preset.heightCm - height))
        }
        return candidates
            .filter { $0.1 <= 0.5 }
            .min(by: { $0.1 < $1.1 })?
            .0
    }

    private func scheduleOtherDwell(at height: Double) {
        if let pendingOtherHeight, abs(pendingOtherHeight - height) <= 0.2 {
            return
        }
        cancelOtherDwell()
        pendingOtherHeight = height
        otherDwellTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(5))
            } catch {
                return
            }
            guard let self else { return }
            self.otherDwellTask = nil
            self.pendingOtherHeight = nil
            guard !self.isPaused,
                  self.controller.state.isConnected,
                  abs(self.controller.speedCmPerSecond) < 0.05,
                  let currentHeight = self.controller.heightCm,
                  abs(currentHeight - height) <= 0.2,
                  self.presetPosture(at: currentHeight) == nil else { return }
            self.transition(to: .other)
        }
    }

    private func cancelOtherDwell() {
        otherDwellTask?.cancel()
        otherDwellTask = nil
        pendingOtherHeight = nil
    }

    private func transition(to posture: StatisticsPosture) {
        guard posture != activePosture else { return }
        closeActiveSession()
        activePosture = posture
        beginSession(posture: posture, at: Date())
    }

    private func beginSession(posture: StatisticsPosture, at date: Date) {
        guard let deskID = activeDeskID,
              let connectionID = activeConnectionID else { return }
        let deskName = settings.savedDesks.first(where: { $0.id == deskID })?.name ?? "Desk"
        let session = PostureStatisticsSession(
            id: UUID(),
            connectionID: connectionID,
            deskID: deskID,
            deskName: deskName,
            posture: posture,
            startedAt: date,
            endedAt: date
        )
        sessions.append(session)
        activeSessionID = session.id
        saveSessions()
        controller.recordDiagnosticEvent("Statistics: started \(posture.title) session for \(deskName)")
    }

    private func updateActiveSessionEnd(at date: Date = Date()) {
        guard let activeSessionID,
              let index = sessions.firstIndex(where: { $0.id == activeSessionID }) else { return }
        sessions[index].endedAt = max(date, sessions[index].startedAt)
        saveSessions()
    }

    private func closeActiveSession() {
        updateActiveSessionEnd()
        activeSessionID = nil
        activePosture = nil
    }

    private func saveSessions() {
        do {
            let url = try Self.storageURL(createDirectory: true)
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: url, options: .atomic)
        } catch {
            controller.recordDiagnosticEvent("Statistics: save failed: \(error.localizedDescription)")
        }
    }

    private static func loadSessions() -> [PostureStatisticsSession] {
        guard let url = try? storageURL(createDirectory: false),
              let data = try? Data(contentsOf: url),
              let sessions = try? JSONDecoder().decode([PostureStatisticsSession].self, from: data) else {
            return []
        }
        return sessions
    }

    private static func storageURL(createDirectory: Bool) throws -> URL {
        let applicationSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: createDirectory
        )
        let directory = applicationSupport.appending(path: "DeskBuddy", directoryHint: .isDirectory)
        if createDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appending(path: "posture-statistics.json")
    }
}