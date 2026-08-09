import Foundation

struct SavedDesk: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
}

struct DeskPreset: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var name: String
    var heightCm: Double
    var symbol: String
    var kind: PresetKind? = .custom

    static let defaults = [
        DeskPreset(name: "Sit", heightCm: 72, symbol: "chair", kind: .sitting),
        DeskPreset(name: "Stand", heightCm: 110, symbol: "figure.stand", kind: .standing),
        DeskPreset(name: "Min", heightCm: DeskProtocol.minimumHeightCm, symbol: "arrow.down.to.line", kind: .minimum),
        DeskPreset(name: "Max", heightCm: DeskProtocol.maximumHeightCm, symbol: "arrow.up.to.line", kind: .maximum)
    ]

    var resolvedKind: PresetKind {
        if let kind { return kind }
        switch name.lowercased() {
        case "sit": return .sitting
        case "stand": return .standing
        case "min": return .minimum
        case "max": return .maximum
        default: return .custom
        }
    }
}

enum PresetKind: String, Codable, CaseIterable {
    case sitting
    case standing
    case minimum
    case maximum
    case custom
}

enum MenuBarPresentation: String, Codable, CaseIterable, Identifiable {
    case symbolAndValue
    case symbol
    case value

    var id: Self { self }
    var title: String {
        switch self {
        case .symbolAndValue: "Symbol & Value"
        case .symbol: "Symbol"
        case .value: "Value"
        }
    }
}

enum HeightPrecision: String, Codable, CaseIterable, Identifiable {
    case whole
    case tenth

    var id: Self { self }
    var title: String { self == .whole ? "87 cm" : "87.4 cm" }
}

enum DeskBuddyTheme: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

enum ConnectionState: Equatable {
    case bluetoothOff
    case idle
    case scanning
    case connecting(String)
    case connected(String)
    case failed(String)

    var title: String {
        switch self {
        case .bluetoothOff: "Bluetooth is Off"
        case .idle: "Not Connected"
        case .scanning: "Searching for Desks …"
        case .connecting(let name): "Connecting to \(name) …"
        case .connected(let name): "Connected to \(name)"
        case .failed(let message): message
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

enum ManualDirection: Equatable {
    case up
    case down
}
