import Combine
import CoreBluetooth
import Foundation
import OSLog

@MainActor
final class DeskController: NSObject, ObservableObject {
    static let shared = DeskController()

    @Published private(set) var state: ConnectionState = .idle
    @Published private(set) var discoveredDesks: [SavedDesk] = []
    @Published private(set) var heightCm: Double?
    @Published private(set) var speedCmPerSecond: Double = 0
    @Published private(set) var targetHeightCm: Double?
    @Published private(set) var isMoving = false
    @Published private(set) var connectedDeskID: UUID?
    @Published private(set) var diagnosticEvents: [String] = []

    private let settings = SettingsStore.shared
    private let logger = Logger(subsystem: "local.opendesk.control", category: "Bluetooth")
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var discoveredPeripherals: [UUID: CBPeripheral] = [:]
    private var commandCharacteristic: CBCharacteristic?
    private var heightCharacteristic: CBCharacteristic?
    private var referenceCharacteristic: CBCharacteristic?
    private var dpgCharacteristic: CBCharacteristic?
    private var manualTimer: Timer?
    private var targetTimer: Timer?
    private var movementDeadline: Date?
    private var manualDirection: ManualDirection?
    private var shouldReconnect = true
    private var hasAttemptedRestore = false
    private var pendingDesk: SavedDesk?
    private var setupComplete = false
    private var connectionWatchdog: Task<Void, Never>?
    private var setupWatchdog: Task<Void, Never>?
    private var hardwareMotionStartedAt: Date?
    private var hardwareMotionDirection: ManualDirection?
    private var lastHardwareTapAt: Date?
    private var lastHardwareTapDirection: ManualDirection?

    private override init() {
        super.init()
        central = CBCentralManager(delegate: self, queue: .main)
    }

    func scan() {
        guard central.state == .poweredOn else {
            state = .bluetoothOff
            return
        }
        discoveredDesks = []
        discoveredPeripherals = [:]
        record("Scan started")
        state = .scanning
        central.scanForPeripherals(
            withServices: [CBUUID(string: DeskProtocol.advertisedService)],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(12))
            if case .scanning = self.state {
                self.central.stopScan()
                self.state = self.discoveredDesks.isEmpty
                    ? .failed("No compatible desk found")
                    : .idle
            }
        }
    }

    func stopScan() {
        central.stopScan()
        if case .scanning = state { state = .idle }
    }

    func connect(to desk: SavedDesk) {
        stopScan()
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
        shouldReconnect = false
        pendingDesk = nil
        stopMovement()
        if let peripheral { central.cancelPeripheralConnection(peripheral) }
        clearConnection()
        state = .idle
        record("Disconnected manually")
    }

    var diagnosticsText: String {
        diagnosticEvents.joined(separator: "\n")
    }

    func startManual(_ direction: ManualDirection) {
        guard state.isConnected, commandCharacteristic != nil else { return }
        stopTimers(sendStop: false)
        manualDirection = direction
        isMoving = true
        sendManualCommand()
        manualTimer = Timer.scheduledTimer(withTimeInterval: 0.55, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sendManualCommand() }
        }
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
        movementDeadline = Date().addingTimeInterval(30)
        isMoving = true
        write(DeskProtocol.wake, to: commandCharacteristic, withResponse: true)
        write(DeskProtocol.stop, to: commandCharacteristic, withResponse: true)
        write(payload, to: referenceCharacteristic, withResponse: true)

        targetTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.continueTargetMovement() }
        }
    }

    func move(to preset: DeskPreset) {
        move(to: preset.heightCm)
    }

    func saveCurrentHeight(as name: String, symbol: String = "star") {
        guard let heightCm else { return }
        settings.presets.append(DeskPreset(name: name, heightCm: heightCm, symbol: symbol))
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
        if let deadline = movementDeadline, Date() >= deadline {
            stopMovement()
            state = .failed("Safety stop after 30 seconds")
            return
        }
        write(payload, to: referenceCharacteristic, withResponse: false)
    }

    private func sendManualCommand() {
        guard let direction = manualDirection else { return }
        write(direction == .up ? DeskProtocol.moveUp : DeskProtocol.moveDown,
              to: commandCharacteristic,
              withResponse: false)
    }

    private func stopTimers(sendStop: Bool) {
        manualTimer?.invalidate()
        targetTimer?.invalidate()
        manualTimer = nil
        targetTimer = nil
        manualDirection = nil
        targetHeightCm = nil
        movementDeadline = nil
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
        if diagnosticEvents.count > 40 { diagnosticEvents.removeFirst(diagnosticEvents.count - 40) }
        logger.info("\(message, privacy: .public)")
    }

    private func processHardwareGesture(speed: Double) {
        guard SettingsStore.shared.doubleTapEnabled, !isMoving else {
            hardwareMotionStartedAt = nil
            hardwareMotionDirection = nil
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
        guard now.timeIntervalSince(startedAt) <= 1.3 else {
            lastHardwareTapAt = nil
            lastHardwareTapDirection = nil
            return
        }

        if lastHardwareTapDirection == finishedDirection,
           let previous = lastHardwareTapAt,
           now.timeIntervalSince(previous) <= 1.4 {
            lastHardwareTapAt = nil
            lastHardwareTapDirection = nil
            let targetKind: PresetKind = finishedDirection == .up ? .standing : .sitting
            if let preset = SettingsStore.shared.presets.first(where: { $0.resolvedKind == targetKind }) {
                record("Double tap detected: \(preset.name)")
                move(to: preset)
            }
        } else {
            lastHardwareTapAt = now
            lastHardwareTapDirection = finishedDirection
        }
    }
}

extension DeskController: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            record("Bluetooth is ready")
            state = .idle
            restoreLastDeskIfPossible()
        case .poweredOff, .unauthorized, .unsupported:
            record("Bluetooth unavailable (state \(central.state.rawValue))")
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
        if let target = targetHeightCm,
           abs(position.heightCm - target) <= 0.5,
           abs(position.speedCmPerSecond) < 0.5 {
            stopMovement()
        }
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didWriteValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        if let error { record("Write error \(characteristic.uuid.uuidString): \(error.localizedDescription)") }
    }
}
