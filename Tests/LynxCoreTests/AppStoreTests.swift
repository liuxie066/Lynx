import Foundation
import Testing
import LynxCore
@testable import LynxApp

@Test @MainActor func appEditsSurviveReopeningAndPreviewNeverSaves() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("configuration.json")
    let store = AppStore(preview: false, configurationURL: url)
    try store.addStock(code: "AAPL")
    try store.addStock(code: "aapl")
    #expect(store.stocks.count == 1)
    var cc = StrategySettings(); cc.enabled = true; cc.minStrike = "200"
    store.settings(stockID: "us.AAPL", strategy: .cc).wrappedValue = cc
    store.portText = "22222"; store.savePort()
    let reopened = AppStore(preview: false, configurationURL: url)
    #expect(reopened.stocks[0].cc == cc)
    #expect(reopened.stocks[0].csp == StrategySettings())
    #expect(reopened.configuration.port == 22222)
    store.portText = "0"; store.savePort()
    #expect(!store.validPort)
    #expect(store.configuration.port == 22222)
    let before = try Data(contentsOf: url)
    let preview = AppStore(preview: true, configurationURL: url)
    try preview.addStock(code: "MSFT")
    preview.portText = "33333"; preview.savePort()
    #expect(try Data(contentsOf: url) == before)
}

@Test @MainActor func unreadableConfigurationBlocksAppWrites() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let url = folder.appendingPathComponent("configuration.json")
    let original = Data("broken config".utf8)
    try original.write(to: url)
    let store = AppStore(preview: false, configurationURL: url)
    #expect(store.storageError != nil)
    try store.addStock(code: "AAPL")
    store.portText = "22222"; store.savePort()
    #expect(try Data(contentsOf: url) == original)
}

@Test @MainActor func unreadableResultsArePreservedWhileConfigurationRemainsWritable() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let results = folder.appendingPathComponent("results.json")
    let original = Data("bad result".utf8); try original.write(to: results)
    let store = AppStore(preview: false, configurationURL: folder.appendingPathComponent("configuration.json"))
    #expect(store.historyError != nil)
    try store.addStock(code: "AAPL")
    #expect(try Data(contentsOf: results) == original)
    #expect(FileManager.default.fileExists(atPath: folder.appendingPathComponent("configuration.json").path))
}
