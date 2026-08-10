import Foundation
import Testing
@testable import DeskBuddy

@Test func defaultPresetsUseEnglishNames() {
    #expect(DeskPreset.defaults.map(\.name) == ["Sit", "Stand", "Min", "Max"])
}

@Test func decodesMinimumHeightAndStoppedSpeed() {
    let position = DeskProtocol.decodePosition(Data([0, 0, 0, 0]))
    #expect(position == DeskProtocol.Position(heightCm: 62, speedCmPerSecond: 0))
}

@Test func decodesPositionAndSignedSpeed() {
    let position = DeskProtocol.decodePosition(Data([0x20, 0x03, 0x9C, 0xFF]))
    #expect(position?.heightCm == 70.0)
    #expect(position?.speedCmPerSecond == -1.0)
}

@Test func targetRoundTrips() {
    #expect(DeskProtocol.encodeTarget(heightCm: 62) == Data([0, 0]))
    #expect(DeskProtocol.encodeTarget(heightCm: 110) == Data([0xC0, 0x12]))
    #expect(DeskProtocol.encodeTarget(heightCm: 127) == Data([0x64, 0x19]))
}

@Test func rejectsOutOfRangeTargetsAndMalformedTelemetry() {
    #expect(DeskProtocol.encodeTarget(heightCm: 61.9) == nil)
    #expect(DeskProtocol.encodeTarget(heightCm: 127.1) == nil)
    #expect(DeskProtocol.decodePosition(Data([0, 0, 0])) == nil)
}

@Test func advertisedServiceIsTheControlService() {
    #expect(DeskProtocol.commandService == DeskProtocol.advertisedService)
    #expect(DeskProtocol.commandCharacteristic.hasPrefix("99FA0002"))
}

@Test func paddleGestureRulesMatchArbitraryPrefixes() {
    let rule = PaddleGestureRule(directions: [.up, .down, .up, .up], presetID: UUID())
    #expect(rule.starts(with: [.up]))
    #expect(rule.starts(with: [.up, .down, .up]))
    #expect(rule.starts(with: rule.directions))
    #expect(!rule.starts(with: [.down]))
    #expect(!rule.starts(with: [.up, .down, .up, .up, .down]))
}
