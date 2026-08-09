import Foundation

enum DeskProtocol {
    static let advertisedService = "99FA0001-338A-1024-8A49-009C0215F78A"
    static let commandService = "99FA0001-338A-1024-8A49-009C0215F78A"
    static let commandCharacteristic = "99FA0002-338A-1024-8A49-009C0215F78A"
    static let dpgService = "99FA0010-338A-1024-8A49-009C0215F78A"
    static let dpgCharacteristic = "99FA0011-338A-1024-8A49-009C0215F78A"
    static let heightService = "99FA0020-338A-1024-8A49-009C0215F78A"
    static let heightCharacteristic = "99FA0021-338A-1024-8A49-009C0215F78A"
    static let referenceService = "99FA0030-338A-1024-8A49-009C0215F78A"
    static let referenceCharacteristic = "99FA0031-338A-1024-8A49-009C0215F78A"

    static let minimumHeightCm = 62.0
    static let maximumHeightCm = 127.0

    static let moveUp = Data([0x47, 0x00])
    static let moveDown = Data([0x46, 0x00])
    static let stop = Data([0xFF, 0x00])
    static let referenceStop = Data([0x01, 0x80])
    static let wake = Data([0xFE, 0x00])
    static let dpgWakePrefix = Data([0x7F, 0x86, 0x00])
    static let dpgWakeSequence = Data([0x7F, 0x86, 0x80] + Array(1...17))

    struct Position: Equatable {
        let heightCm: Double
        let speedCmPerSecond: Double
    }

    static func decodePosition(_ data: Data) -> Position? {
        guard data.count == 4 else { return nil }
        let bytes = [UInt8](data)
        let rawHeight = UInt16(bytes[0]) | (UInt16(bytes[1]) << 8)
        let rawSpeedBits = UInt16(bytes[2]) | (UInt16(bytes[3]) << 8)
        let rawSpeed = Int16(bitPattern: rawSpeedBits)

        return Position(
            heightCm: minimumHeightCm + Double(rawHeight) / 100.0,
            speedCmPerSecond: Double(rawSpeed) / 100.0
        )
    }

    static func encodeTarget(heightCm: Double) -> Data? {
        guard heightCm >= minimumHeightCm, heightCm <= maximumHeightCm else { return nil }
        let raw = UInt16(((heightCm - minimumHeightCm) * 100.0).rounded())
        return Data([UInt8(raw & 0xFF), UInt8((raw >> 8) & 0xFF)])
    }
}
