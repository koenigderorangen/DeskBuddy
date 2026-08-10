import Combine
import CoreBluetooth
import Foundation
import OSLog

@MainActor
final class DeskController: NSObject, ObservableObject {
    static let shared = DeskController()
    static let targetMovementTimeout: TimeInterval = 30
    static let targetStartupTimeout: TimeInterval = 5
    static let targetRearmInterval: TimeInterval = 0.8
    static let hardwareTapMaximumDuration: TimeInterval = 1.3
    static let hardwareTapInterval: TimeInterval = 1.4

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var discoveredDesks: [SavedDesk] = []
    @Published private(set) var heightCm: Double?
    @Published private(set) var speedCmPerSecond: Double = 0
    @Published private(set) var targetHeightCm: Double?
    @Published private(set) var isMoving = false
    @Published private(set) var isScanning = false
    @Published private(set) var connectedDeskID: UUID?
    @Published private(set) var diagnosticEvents: [String] = []

    private let settings = SettingsStore.shared
    private let logger = Logger(subsystem: "local.opendesk.control", category: "Bluetooth")
    private lazy var central = CBCentralManager(delegate: self, queue: .main)
    private var peripheral: CBPeripheral?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var commandCharacteristic: CBCharacteristic?
    private var heightCharacteristic: CBCharacteristic?
    private var referenceCharacteristic: CBCharacteristic?
    private var dpgCharacteristic: CBCharacteristic?
    private var manualTimer: Timer?
    private var targetTimer: Timer?
    private var movementDeadline: Date?
    private var targetStartupDeadline: Date?
    private var nextTargetRearmAt: Date?
    private var targetStartingHeightCm: Double?
    private var targetMotionStarted = false
    private var targetRearmCount = 0
    private var manualDirection: ManualDirection?
    private var shouldReconnect = true
    private var hasAttemptedRestore = false
    private var pendingDesk: SavedDesk?
    private var setupComplete = false
    private var connectionWatchdog: Task<Void, Never>?
    private var setupWatchdog: Task<Void, Never>?
    private var wakeReconnectTask: Task<Void, Never>?
    private var reconnectDeskAfterWake: SavedDesk?
    private var systemIsSleeping = false
    private var hardwareMotionStartedAt: Date?
    private var hardwareMotionDirection: ManualDirection?
    private var hardwareTapSequence: [ManualDirection] = []
    private var lastHardwareTapAt: Date?
    private var pendingPaddleGestureRule: PaddleGestureRule?
    private var pendingHardwareGestureTask: Task<Void, Never>?

    private override init() {
        super.init()
    }

    var bluetoothAuthorization: CBManagerAuthorization {
        CBManager.authorization
    }

    var bluetoothState: CBManagerState {
        central.state
    }

    func startBluetooth() {
        _ = central
    }

    func systemWillSleep() {
        systemIsSleeping = true
        guard settings.autoReconnect,
                            pendingDesk != nil
                                || state.isConnected
                                || peripheral?.state == .connecting
                                || peripheral?.state == .connected,
              let deskID = pendingDesk?.id ?? connectedDeskID ?? peripheral?.identifier else {
            reconnectDeskAfterWake = nil
            return
        }
        reconnectDeskAfterWake = pendingDesk
            ?? settings.savedDesks.first(where: { $0.id == deskID })
            ?? SavedDesk(id: deskID, name: peripheral?.name ?? "IDÅSEN Desk")
        record("System sleep: reconnect armed")
    }

    func systemDidWake() {
        systemIsSleeping = false
        guard settings.autoReconnect, reconnectDeskAfterWake != nil else { return }
        wakeReconnectTask?.cancel()
        wakeReconnectTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(1.5))
            } catch {
                return
            }
            guard let self else { return }
            self.wakeReconnectTask = nil
            self.attemptWakeReconnect()
        }
    }

    private func attemptWakeReconnect() {
        guard !systemIsSleeping,
              settings.autoReconnect,
              let desk = reconnectDeskAfterWake else { return }
        guard central.state == .poweredOn else {
            record("System wake: waiting for Bluetooth")
            return
        }

        reconnectDeskAfterWake = nil
        pendingDesk = nil
        shouldReconnect = true
        record("System wake: reconnecting to \(desk.name)")
        stopScan()
        if let current = peripheral,
           current.state == .connected || current.state == .connecting {
            pendingDesk = desk
            stopTimers(sendStop: false)
            state = .connecting(desk.name)
            central.cancelPeripheralConnection(current)
        } else {
            clearConnection()
            state = .idle
            connect(to: desk)
        }
    }

    func scan() {
        guard central.state == .poweredOn else {
            state = .bluetoothOff
            return
        }
        discoveredDesks = []
        discoveredPeripherals = [:]
        record("Scan started")
        isScanning = true
        state = activeConnectionState ?? .scanning
        central.scanForPeripherals(
            withServices: [CBUUID(string: DeskProtocol.advertisedService)],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(12))
            if self.isScanning {
                self.central.stopScan()
                self.isScanning = false
                self.state = self.activeConnectionState
                    ?? (self.discoveredDesks.isEmpty ? .failed("No compatible desk found") : .idle)
            }
        }
    }

    func stopScan() {
        central.stopScan()
        isScanning = false
        if case .scanning = state { state = activeConnectionState ?? .idle }
    }

    private var activeConnectionState: ConnectionState? {
        guard setupComplete,
              peripheral?.state == .connected,
              let connectedDeskID else { return nil }
        let name = settings.savedDesks.first(where: { $0.id == connectedDeskID })?.name
            ?? peripheral?.name
            ?? "IDÅSEN Desk"
        return .connected(name)
    }

    func connect(to desk: SavedDesk) {
        stopScan()
        if desk.id == connectedDeskID, let activeConnectionState {
            state = activeConnectionState
            return
        }
        guard let candidate = discoveredPeripherals[desk.id]
            ?? central.retrievePeripherals(withIdentifiers: [desk.id]).first else {
            record("Desk is no longer in the Bluetooth cache")
            state = .failed("Desk is no longer reachable — please scan again")
            return
        }
        if let current = peripheral, current.identifier != desk.id,
           current.state == .connected || current.state == .connecting {
            pendingDesk = desk
            shouldReconnect = false
            stopTimers(sendStop: true)
            state = .connecting(desk.name)
            central.cancelPeripheralConnection(current)
            return
        }
        connect(candidate, displayName: desk.name)
    }

    func disconnect() {
        wakeReconnectTask?.cancel()
        wakeReconnectTask = nil
        reconnectDeskAfterWake = nil
        shouldReconnect = false
        pendingDesk = nil
        stopMovement()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        clearConnection()
        state = .idle
        record("Disconnected manually")
    }

    var diagnosticsReport: String {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Development"
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "Unknown"
        let deskIdentifier = connectedDeskID.map { String($0.uuidString.prefix(8)) } ?? "None"
        let height = heightCm.map { String(format: "%.1f cm", $0) } ?? "Unavailable"
        let generatedAt = ISO8601DateFormatter().string(from: Date())
        let diagnosticsText = diagnosticEvents.joined(separator: "\n")
        return """
        DeskBuddy Diagnostics
        Generated: \(generatedAt)

        App: \(appVersion) (\(buildNumber))
        macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)
        State: \(state.title)
        Scanning: \(isScanning ? "Yes" : "No")
        Connected desk: \(deskIdentifier)
        Bluetooth manager state: \(central.state.rawValue)
        Peripheral state: \(peripheral?.state.rawValue.description ?? "None")
        Setup complete: \(setupComplete ? "Yes" : "No")
        Command characteristic: \(commandCharacteristic == nil ? "Missing" : "Ready")
        Height characteristic: \(heightCharacteristic == nil ? "Missing" : "Ready")
        Reference characteristic: \(referenceCharacteristic == nil ? "Missing" : "Ready")
        Height: \(height)
        Speed: \(String(format: "%.2f cm/s", speedCmPerSecond))
        Moving: \(isMoving ? "Yes" : "No")

        Event Log
        ---------
        \(diagnosticsText.isEmpty ? "No diagnostic events recorded." : diagnosticsText)
        """
    }

    func startManual(_ direction: ManualDirection) {
        guard state.isConnected, commandCharacteristic != nil else { return }
        stopTimers(sendStop: false)
        manualDirection = direction
        isMoving = true
        sendManualCommand()
        let timer = Timer(timeInterval: 0.55, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendManualCommand() }
        }
        RunLoop.main.add(timer, forMode: .common)
        manualTimer = timer
    }

    func stopMovement() {
        stopTimers(sendStop: true)
    }

    func move(to requestedHeightCm: Double) {
        guard state.isConnected,
              heightCm != nil,
              let payload = DeskProtocol.encodeTarget(heightCm: requestedHeightCm),
              referenceCharacteristic != nil,
              commandCharacteristic != nil else {
            state = .failed("Cannot move to target — no valid height reading yet")
            return
        }

        stopTimers(sendStop: true)
        targetHeightCm = requestedHeightCm
        let now = Date()
        movementDeadline = now.addingTimeInterval(Self.targetMovementTimeout)
        targetStartupDeadline = now.addingTimeInterval(Self.targetStartupTimeout)
        nextTargetRearmAt = now.addingTimeInterval(Self.targetRearmInterval)
        targetStartingHeightCm = heightCm
        targetMotionStarted = false
        targetRearmCount = 0
        isMoving = true
        armTargetMovement(payload, withResponse: true)

        let timer = Timer(timeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.continueTargetMovement() }
        }
        RunLoop.main.add(timer, forMode: .common)
        targetTimer = timer
    }

    func move(to preset: DeskPreset) {
        move(to: preset.heightCm)
    }

    private func connect(_ candidate: CBPeripheral, displayName: String) {
        shouldReconnect = true
        setupComplete = false
        peripheral = candidate
        candidate.delegate = self
        state = .connecting(displayName)
        record("Connecting to \(displayName) [\(candidate.identifier.uuidString.prefix(8))]")
        central.connect(candidate, options: [CBConnectPeripheralOptionNotifyOnDisconnectionKey: true])
        connectionWatchdog?.cancel()
        connectionWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self,
                  self.peripheral?.identifier == candidate.identifier,
                  !self.state.isConnected else { return }
            self.record("Timeout: no Bluetooth connection after 20 seconds")
            self.central.cancelPeripheralConnection(candidate)
            self.clearConnection()
            self.state = .failed("Connection timed out after 20 seconds")
        }
    }

    private func restoreLastDeskIfPossible() {
        guard !hasAttemptedRestore, settings.autoReconnect, let id = settings.lastDeskID else { return }
        hasAttemptedRestore = true
        if let saved = settings.savedDesks.first(where: { $0.id == id }),
           let candidate = central.retrievePeripherals(withIdentifiers: [id]).first {
            connect(candidate, displayName: saved.name)
        } else {
            scan()
        }
    }

    private func remember(_ peripheral: CBPeripheral) -> SavedDesk {
        let name = peripheral.name ?? "IDÅSEN Desk"
        let desk = SavedDesk(id: peripheral.identifier, name: name)
        if let index = settings.savedDesks.firstIndex(where: { $0.id == desk.id }) {
            settings.savedDesks[index] = desk
        } else {
            settings.savedDesks.append(desk)
        }
        settings.lastDeskID = desk.id
        connectedDeskID = desk.id
        return desk
    }

    private func clearConnection() {
        connectionWatchdog?.cancel()
        setupWatchdog?.cancel()
        stopTimers(sendStop: false)
        peripheral = nil
        commandCharacteristic = nil
        heightCharacteristic = nil
        referenceCharacteristic = nil
        dpgCharacteristic = nil
        connectedDeskID = nil
        setupComplete = false
        heightCm = nil
        speedCmPerSecond = 0
    }

    private func finishSetupIfReady() {
        guard !setupComplete, let peripheral, commandCharacteristic != nil,
              heightCharacteristic != nil, referenceCharacteristic != nil else { return }
        setupComplete = true
        setupWatchdog?.cancel()
        let desk = remember(peripheral)
        state = .connected(desk.name)
        record("Ready: controls and height telemetry found")

        if let dpgCharacteristic {
            write(DeskProtocol.dpgWakePrefix, to: dpgCharacteristic, withResponse: true)
            write(DeskProtocol.dpgWakeSequence, to: dpgCharacteristic, withResponse: true)
        }
        write(DeskProtocol.wake, to: commandCharacteristic, withResponse: true)
        peripheral.setNotifyValue(true, for: heightCharacteristic!)
        peripheral.readValue(for: heightCharacteristic!)
    }

    private func continueTargetMovement() {
        guard let target = targetHeightCm,
              let payload = DeskProtocol.encodeTarget(heightCm: target),
              let referenceCharacteristic else {
            stopMovement()
            return
        }
        if let current = heightCm, abs(current - target) <= 0.5, abs(speedCmPerSecond) < 0.5 {
            stopMovement()
            return
        }
        let now = Date()
        if !targetMotionStarted,
           let startupDeadline = targetStartupDeadline,
           now >= startupDeadline {
            stopMovement()
            record("Target movement did not start after \(targetRearmCount + 1) activation attempts")
            return
        }
        if let deadline = movementDeadline, Date() >= deadline {
            stopMovement()
            record("Target movement timed out before the requested height was reached")
            return
        }
        if !targetMotionStarted,
           let nextRearmAt = nextTargetRearmAt,
           now >= nextRearmAt {
            targetRearmCount += 1
            armTargetMovement(payload, withResponse: false)
            self.nextTargetRearmAt = now.addingTimeInterval(Self.targetRearmInterval)
            record("Rearmed target movement (attempt \(targetRearmCount + 1))")
            return
        }
        write(payload, to: referenceCharacteristic, withResponse: false)
    }

    private func armTargetMovement(_ payload: Data, withResponse: Bool) {
        write(DeskProtocol.wake, to: commandCharacteristic, withResponse: withResponse)
        write(DeskProtocol.stop, to: commandCharacteristic, withResponse: withResponse)
        write(payload, to: referenceCharacteristic, withResponse: withResponse)
    }

    private func sendManualCommand() {
        guard let direction = manualDirection else { return }
        write(direction == .up ? DeskProtocol.moveUp : DeskProtocol.moveDown,
              to: commandCharacteristic,
              withResponse: false)
    }

    private func stopTimers(sendStop: Bool) {
        resetHardwareGestureRecognition()
        manualTimer?.invalidate()
        targetTimer?.invalidate()
        manualTimer = nil
        targetTimer = nil
        manualDirection = nil
        targetHeightCm = nil
        movementDeadline = nil
        targetStartupDeadline = nil
        nextTargetRearmAt = nil
        targetStartingHeightCm = nil
        targetMotionStarted = false
        targetRearmCount = 0
        isMoving = false
        guard sendStop else { return }
        write(DeskProtocol.stop, to: commandCharacteristic, withResponse: false)
        write(DeskProtocol.referenceStop, to: referenceCharacteristic, withResponse: false)
    }

    private func write(_ data: Data, to characteristic: CBCharacteristic?, withResponse: Bool) {
        guard let peripheral, let characteristic else { return }
        let requestedType: CBCharacteristicWriteType = withResponse ? .withResponse : .withoutResponse
        let type: CBCharacteristicWriteType
        if withResponse, characteristic.properties.contains(.write) {
            type = requestedType
        } else if characteristic.properties.contains(.writeWithoutResponse) {
            type = .withoutResponse
        } else if characteristic.properties.contains(.write) {
            type = .withResponse
        } else {
            return
        }
        peripheral.writeValue(data, for: characteristic, type: type)
    }

    private func record(_ message: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let line = "\(formatter.string(from: Date()))  \(message)"
        diagnosticEvents.append(line)
        if diagnosticEvents.count > 200 { diagnosticEvents.removeFirst(diagnosticEvents.count - 200) }
        logger.info("\(message, privacy: .public)")
    }

    private func processHardwareGesture(speed: Double) {
        guard settings.paddleGesturesEnabled, !isMoving else {
            resetHardwareGestureRecognition()
            return
        }

        let direction: ManualDirection? = if speed > 0.15 {
            .up
        } else if speed < -0.15 {
            .down
        } else {
            nil
        }

        if let direction, hardwareMotionDirection == nil {
            pendingHardwareGestureTask?.cancel()
            pendingHardwareGestureTask = nil
            hardwareMotionDirection = direction
            hardwareMotionStartedAt = Date()
            return
        }

        guard direction == nil,
              let finishedDirection = hardwareMotionDirection,
              let startedAt = hardwareMotionStartedAt else { return }

        hardwareMotionDirection = nil
        hardwareMotionStartedAt = nil
        let now = Date()
        guard now.timeIntervalSince(startedAt) <= Self.hardwareTapMaximumDuration else {
            resetHardwareTapSequence()
            return
        }

        registerHardwareTap(finishedDirection, startedAt: startedAt, finishedAt: now)
    }

    private func registerHardwareTap(
        _ direction: ManualDirection,
        startedAt: Date,
        finishedAt: Date
    ) {
        if let previous = lastHardwareTapAt,
           startedAt.timeIntervalSince(previous) > Self.hardwareTapInterval {
            let deferredRule = pendingPaddleGestureRule
            resetHardwareTapSequence()
            if let deferredRule {
                performPaddleGesture(deferredRule)
                return
            }
        }

        hardwareTapSequence.append(direction)
        lastHardwareTapAt = finishedAt

        let matchingRule = settings.paddleGestureRules.first { $0.directions == hardwareTapSequence }
        let hasLongerRule = settings.paddleGestureRules.contains {
            $0.directions.count > hardwareTapSequence.count && $0.starts(with: hardwareTapSequence)
        }

        if let matchingRule, !hasLongerRule {
            performPaddleGesture(matchingRule)
            resetHardwareTapSequence()
        } else if matchingRule != nil || hasLongerRule {
            deferPaddleGesture(matchingRule)
        } else if let pendingPaddleGestureRule {
            performPaddleGesture(pendingPaddleGestureRule)
            resetHardwareTapSequence()
        } else {
            resetHardwareTapSequence()
        }
    }

    private func deferPaddleGesture(_ rule: PaddleGestureRule?) {
        pendingPaddleGestureRule = rule
        let expectedSequence = hardwareTapSequence
        let continuationDelay = rule == nil
            ? Self.hardwareTapInterval
            : settings.paddleGestureContinuationDelay
        pendingHardwareGestureTask?.cancel()
        pendingHardwareGestureTask = Task { @MainActor [weak self] in
            do {
            try await Task.sleep(for: .seconds(continuationDelay))
            } catch {
                return
            }
            guard let self, self.hardwareTapSequence == expectedSequence else { return }
            if let rule {
                self.performPaddleGesture(rule)
            }
            self.resetHardwareTapSequence()
        }
    }

    private func performPaddleGesture(_ rule: PaddleGestureRule) {
        guard settings.paddleGesturesEnabled,
              let currentRule = settings.paddleGestureRules.first(where: {
                  $0.id == rule.id && $0.directions == rule.directions
              }),
              let preset = settings.preset(for: currentRule) else { return }
        record("\(currentRule.title) detected: \(preset.name)")
        move(to: preset)
    }

    private func resetHardwareGestureRecognition() {
        hardwareMotionStartedAt = nil
        hardwareMotionDirection = nil
        resetHardwareTapSequence()
    }

    private func resetHardwareTapSequence() {
        pendingHardwareGestureTask?.cancel()
        pendingHardwareGestureTask = nil
        pendingPaddleGestureRule = nil
        hardwareTapSequence = []
        lastHardwareTapAt = nil
    }
}

extension DeskController: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            record("Bluetooth is ready")
            state = .idle
            if reconnectDeskAfterWake != nil {
                attemptWakeReconnect()
            } else {
                restoreLastDeskIfPossible()
            }
        case .poweredOff, .unauthorized, .unsupported:
            record("Bluetooth unavailable (state \(central.state.rawValue))")
            central.stopScan()
            isScanning = false
            clearConnection()
            state = .bluetoothOff
        default:
            break
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        let desk = SavedDesk(id: peripheral.identifier, name: peripheral.name ?? "IDÅSEN Desk")
        discoveredPeripherals[peripheral.identifier] = peripheral
        record("Found: \(desk.name), signal \(RSSI)")
        if !discoveredDesks.contains(where: { $0.id == desk.id }) {
            discoveredDesks.append(desk)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        connectionWatchdog?.cancel()
        record("Bluetooth connected; discovering desk services")
        peripheral.delegate = self
        peripheral.discoverServices([
            CBUUID(string: DeskProtocol.commandService),
            CBUUID(string: DeskProtocol.dpgService),
            CBUUID(string: DeskProtocol.heightService),
            CBUUID(string: DeskProtocol.referenceService)
        ])
        setupWatchdog?.cancel()
        setupWatchdog = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            guard !Task.isCancelled, let self, !self.setupComplete else { return }
            self.record("Timed out while discovering desk services")
            self.central.cancelPeripheralConnection(peripheral)
            self.state = .failed("Connected, but desk services are not responding")
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        record("Connection failed: \(error?.localizedDescription ?? "unknown error")")
        clearConnection()
        state = .failed(error?.localizedDescription ?? "Connection failed")
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        timestamp: CFAbsoluteTime,
        isReconnecting: Bool,
        error: Error?
    ) {
        record("Bluetooth disconnected: \(error?.localizedDescription ?? "no error reported")")
        stopTimers(sendStop: false)
        commandCharacteristic = nil
        heightCharacteristic = nil
        referenceCharacteristic = nil
        dpgCharacteristic = nil
        heightCm = nil
        connectedDeskID = nil
        setupComplete = false
        state = .idle
        if systemIsSleeping {
            record("Reconnect deferred until system wake")
            return
        }
        if let nextDesk = pendingDesk {
            pendingDesk = nil
            shouldReconnect = true
            connect(to: nextDesk)
            return
        }
        if shouldReconnect, settings.autoReconnect {
            let desk = settings.savedDesks.first(where: { $0.id == peripheral.identifier })
                ?? SavedDesk(id: peripheral.identifier, name: peripheral.name ?? "IDÅSEN Desk")
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(2))
                self.connect(to: desk)
            }
        }
    }
}

extension DeskController: @preconcurrency CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            record("Service error: \(error.localizedDescription)")
            state = .failed("Could not discover services: \(error.localizedDescription)")
            return
        }
        record("\(peripheral.services?.count ?? 0) desk services found")
        peripheral.services?.forEach { peripheral.discoverCharacteristics(nil, for: $0) }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        if let error { record("Characteristic error: \(error.localizedDescription)") }
        for characteristic in service.characteristics ?? [] {
            record("Characteristic \(characteristic.uuid.uuidString)")
            switch characteristic.uuid.uuidString.uppercased() {
            case DeskProtocol.commandCharacteristic: commandCharacteristic = characteristic
            case DeskProtocol.heightCharacteristic: heightCharacteristic = characteristic
            case DeskProtocol.referenceCharacteristic: referenceCharacteristic = characteristic
            case DeskProtocol.dpgCharacteristic: dpgCharacteristic = characteristic
            default: break
            }
        }
        finishSetupIfReady()
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error {
            record("Read error: \(error.localizedDescription)")
            return
        }
        guard characteristic.uuid.uuidString.caseInsensitiveCompare(DeskProtocol.heightCharacteristic) == .orderedSame,
              let data = characteristic.value,
              let position = DeskProtocol.decodePosition(data) else { return }
        heightCm = position.heightCm
        speedCmPerSecond = position.speedCmPerSecond
        processHardwareGesture(speed: position.speedCmPerSecond)
        acknowledgeTargetMotion(with: position)
        if targetMotionStarted,
           let target = targetHeightCm,
           abs(position.heightCm - target) > 0.5,
              position.speedCmPerSecond == 0 {
            record("Target movement stopped from the physical paddle")
            stopMovement()
            return
        }
        if let target = targetHeightCm,
           abs(position.heightCm - target) <= 0.5,
           abs(position.speedCmPerSecond) < 0.5 {
            stopMovement()
        }
    }

    private func acknowledgeTargetMotion(with position: DeskProtocol.Position) {
        guard !targetMotionStarted,
              let target = targetHeightCm,
              let startingHeight = targetStartingHeightCm else { return }
        let direction = target - startingHeight
        let heightDelta = position.heightCm - startingHeight
        guard abs(heightDelta) >= 0.05,
              direction * heightDelta > 0,
              direction * position.speedCmPerSecond > 0 else { return }
        targetMotionStarted = true
        targetStartupDeadline = nil
        nextTargetRearmAt = nil
        record("Target movement started")
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error { record("Write error \(characteristic.uuid.uuidString): \(error.localizedDescription)") }
    }
}
