import Foundation
import Testing
@testable import LynxCore

@Test func referenceFrameAndCorruption() throws {
    // Independently specified header: protocol 1001, JSON, request 7, two-byte body.
    let expected = Data([0x46,0x54,0xE9,0x03,0,0,1,0,7,0,0,0,2,0,0,0,
                         0xBF,0x21,0xA9,0xE8,0xFB,0xC5,0xA3,0x84,0x6F,0xB0,
                         0x5B,0x4F,0xA0,0x85,0x9E,0x09,0x17,0xB2,0x20,0x2F] +
                        Array(repeating: UInt8(0), count: 8) + [0x7B,0x7D])
    let encoded = try OpenDFrame(protocolID: 1001, sequenceNumber: 7, body: Data("{}".utf8)).encoded()
    #expect(encoded == expected)
    let header = Data(expected.prefix(44))
    #expect(try OpenDFrame.decode(header: header, body: Data("{}".utf8)).sequenceNumber == 7)
    #expect(throws: OpenDError.checksum) { try OpenDFrame.decode(header: header, body: Data("[]".utf8)) }
    var oversized = header
    oversized.replaceSubrange(12..<16, with: [0xFF,0xFF,0xFF,0x7F])
    #expect(throws: OpenDError.oversizedFrame) { try OpenDFrame.bodyLength(header: oversized) }
    var badFormat = header; badFormat[6] = 0
    #expect(throws: OpenDError.malformedFrame) { try OpenDFrame.bodyLength(header: badFormat) }
    #expect(throws: OpenDError.malformedFrame) { try OpenDFrame.bodyLength(header: Data()) }
}

@Test func missingQuoteFieldsRemainUnknown() throws {
    let quote = try JSONDecoder().decode(Snapshot.self, from: Data(#"{"basic":{"security":{"market":11,"code":"TEST"}},"optionExData":{"openInterest":0}}"#.utf8))
    #expect(quote.basic.curPrice == nil)
    #expect(quote.optionExData?.contractSize == nil)
    #expect(quote.optionExData?.contractMultiplier == nil)
    #expect(quote.optionExData?.openInterest == 0)
    #expect(!quote.missingOptionFields.contains("openInterest"))
    #expect(quote.missingOptionFields.contains("contractMultiplier"))
}

@Test func directionSettingsAreIndependentAndValidated() throws {
    var stock = try WatchStock(market: .hk, code: "700")
    #expect(stock.code == "00700")
    stock.csp.enabled = true
    #expect(stock.csp.validationMessage(for: .csp) != nil)
    #expect(stock.cc.enabled == false)
    stock.cc.enabled = true
    #expect(stock.cc.validationMessage(for: .cc) == nil) // No cost is required.
    stock.csp.maxStrike = "200"; stock.csp.minStrike = "250"
    #expect(stock.csp.validationMessage(for: .csp) != nil)
    stock.csp.minStrike = "100"; stock.csp.minDTE = "1.5"
    #expect(stock.csp.validationMessage(for: .csp) != nil)
    stock.csp.minDTE = "15"; stock.csp.maxDTE = "10"
    #expect(stock.csp.validationMessage(for: .csp) != nil)
    stock.csp.maxDTE = "30"; stock.csp.maxAbsoluteDelta = "nan"
    #expect(stock.csp.validationMessage(for: .csp) != nil)
    stock.csp.maxAbsoluteDelta = "0.35"
    #expect(stock.csp.validationMessage(for: .csp) == nil)
    #expect(throws: ConfigurationError.self) { try WatchStock(market: .us, code: "AAPL;rm") }
}

@Test func configurationRoundTripAndCorruptionPreservation() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let file = ConfigurationFile(url: folder.appendingPathComponent("settings.json"))
    #expect(try file.load() == AppConfiguration())
    var configuration = AppConfiguration()
    configuration.port = 22222
    configuration.stocks = [try WatchStock(market: .us, code: "aapl")]
    configuration.stocks[0].cc.maxStrike = "222.25"
    try file.save(configuration)
    #expect(try file.load() == configuration)
    let corrupt = Data("broken config".utf8)
    try corrupt.write(to: file.url)
    #expect(throws: DecodingError.self) { try file.load() }
    #expect(try Data(contentsOf: file.url) == corrupt)
    configuration.schemaVersion = 2
    try JSONEncoder().encode(configuration).write(to: file.url)
    #expect(throws: ConfigurationError.self) { try file.load() }
    configuration.schemaVersion = 1
    configuration.stocks.append(configuration.stocks[0])
    try JSONEncoder().encode(configuration).write(to: file.url)
    #expect(throws: ConfigurationError.self) { try file.load() }
}
