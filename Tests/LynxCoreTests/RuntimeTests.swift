import Foundation
import Testing
import LynxCore
@testable import LynxApp

actor ScanCounter {
    var count = 0
    func step() { count += 1 }
}
@Test @MainActor func refreshIsSingleFlightAndMarketFailuresStayIndependent() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = AppStore(preview: false, configurationURL: folder.appendingPathComponent("configuration.json"))
    try store.addStock(code: "AAPL")
    var setting = StrategySettings(); setting.enabled = true
    store.settings(stockID: "us.AAPL", strategy: .cc).wrappedValue = setting
    store.market = .hk; try store.addStock(code: "700")
    store.settings(stockID: "hk.00700", strategy: .cc).wrappedValue = setting
    let count = ScanCounter()
    store.scan = { _, market, stocks in
        await count.step(); try await Task.sleep(for: .milliseconds(15))
        if market == .hk { throw AnalysisError.message("fixture HK failure") }
        return .result(MarketResult(market: market, startedAt: Date(), completedAt: Date(), stocks: stocks.map { StockResult(stock: $0, strategy: .cc) }))
    }
    store.refresh(); store.refresh()
    while store.refreshing { try await Task.sleep(for: .milliseconds(5)) }
    #expect(await count.count == 2)
    #expect(store.record(.us).lastSuccess != nil)
    #expect(store.record(.hk).lastSuccess == nil)
    #expect(store.record(.hk).message.contains("fixture HK failure"))
    let success = store.record(.us).lastSuccess
    store.scan = { _, _, _ in throw AnalysisError.message("fixture disconnected") }
    store.refresh()
    while store.refreshing { try await Task.sleep(for: .milliseconds(5)) }
    #expect(store.record(.us).lastSuccess == success)
    #expect(store.record(.us).result != nil && store.record(.us).stale)
    let reopened = AppStore(preview: false, configurationURL: folder.appendingPathComponent("configuration.json"))
    #expect(reopened.record(.us).result != nil && reopened.record(.us).stale)
}
@Test @MainActor func automaticRefreshRequiresDueAndConfigurationChangeCancelsOldResult() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = AppStore(preview: false, configurationURL: folder.appendingPathComponent("configuration.json"))
    try store.addStock(code: "AAPL")
    var setting = StrategySettings(); setting.enabled = true
    store.settings(stockID: "us.AAPL", strategy: .cc).wrappedValue = setting
    let count = ScanCounter()
    store.scan = { _, market, _ in await count.step(); try await Task.sleep(for: .milliseconds(40)); return .closed("fixture closed") }
    store.refresh(manual: false)
    #expect(!store.refreshing)
    var preferences = Preferences(); preferences.refreshMinutes = 10; store.setPreferences(preferences)
    let now = Date()
    store.refresh(manual: false, now: now)
    while store.refreshing { try await Task.sleep(for: .milliseconds(5)) }
    store.refresh(manual: false, now: now.addingTimeInterval(599))
    #expect(!store.refreshing)
    #expect(await count.count == 1)
    store.refresh(manual: false, now: now.addingTimeInterval(600))
    setting.maxDTE = "30"
    store.settings(stockID: "us.AAPL", strategy: .cc).wrappedValue = setting
    while store.refreshing { try await Task.sleep(for: .milliseconds(5)) }
    #expect(store.record(.us).result == nil)
    #expect(store.record(.us).baseline.isEmpty)
}
@Test @MainActor func agentWritesUseSameValidationAndRejectOutOfScopeCapabilities() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = AppStore(preview: false, configurationURL: folder.appendingPathComponent("configuration.json"))
    try store.addStock(code: "AAPL")
    func call(_ command: String, _ args: [String: String] = [:]) async throws -> [String: Any] {
        let result = await store.agentHandle(try JSONEncoder().encode(AgentRequest(command: command, arguments: args)))
        return try #require(JSONSerialization.jsonObject(with: result) as? [String: Any])
    }
    let invalid = try await call("strategy.set", ["market":"us","symbol":"AAPL","strategy":"CSP","enabled":"true"])
    #expect(invalid["ok"] as? Bool == false)
    #expect(!store.configuration.stocks[0].csp.enabled)
    let valid = try await call("strategy.set", ["market":"us","symbol":"AAPL","strategy":"CSP","enabled":"true","maxStrike":"200"])
    #expect(valid["ok"] as? Bool == true)
    #expect(store.configuration.stocks[0].csp.maxStrike == "200")
    let badSettings = try await call("settings.set", ["port":"22222","refreshMinutes":"3"])
    #expect(badSettings["ok"] as? Bool == false)
    #expect(store.configuration.port == 11111)
    for command in ["trade", "holdings", "fees.set"] { #expect(try await call(command)["ok"] as? Bool == false) }
    let after = AppStore(preview: false, configurationURL: folder.appendingPathComponent("configuration.json"))
    #expect(after.configuration.stocks[0].csp.maxStrike == "200")
}
@Test func agentTransportRoundTripsAndStopsWithoutAnotherServer() async throws {
    let directory = "/tmp/lx-test-" + String(UUID().uuidString.prefix(8))
    defer { try? FileManager.default.removeItem(atPath: directory) }
    var server: AgentServer? = try AgentServer(directory: directory) { input in input }
    let message = try JSONEncoder().encode(AgentRequest(command: "status"))
    let output = try await Task.detached { try AgentTransport.call(message, socketPath: directory + "/agent.sock") }.value
    #expect(output == message)
    #expect(throws: (any Error).self) { _ = try AgentServer(directory: directory) { $0 } }
    server?.stop(); server = nil
}

@Test @MainActor func skillInstallUpdateAndUninstallPreserveUnmanagedFiles() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let executable = URL(fileURLWithPath: "/Applications/Lynx.app/Contents/MacOS/Lynx")
    for agent in AgentSkill.allCases {
        let target = folder.appendingPathComponent(agent.rawValue)
        try agent.install(executable: executable, targetFolder: target)
        let original = try String(contentsOf: target.appendingPathComponent("SKILL.md"), encoding: .utf8)
        #expect(original.contains("--agent") && original.contains("managed-by-lynx-v1"))
        try agent.install(executable: executable, targetFolder: target)
        try Data("keep".utf8).write(to: target.appendingPathComponent("user-note.txt"))
        try agent.uninstall(targetFolder: target)
        #expect(FileManager.default.fileExists(atPath: target.appendingPathComponent("user-note.txt").path))
        #expect(throws: (any Error).self) { try agent.install(executable: executable, targetFolder: target) }
    }
}
@Test @MainActor func sleepingPreventsNewRefreshAndWakeDoesNotQueueDuplicates() async throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = AppStore(preview: false, configurationURL: folder.appendingPathComponent("configuration.json"))
    try store.addStock(code: "AAPL")
    var setting = StrategySettings(); setting.enabled = true
    store.settings(stockID: "us.AAPL", strategy: .cc).wrappedValue = setting
    var prefs = Preferences(); prefs.refreshMinutes = 10; store.setPreferences(prefs)
    let count = ScanCounter()
    store.scan = { _, _, _ in await count.step(); try await Task.sleep(for: .milliseconds(30)); return .closed("closed") }
    store.systemWillSleep(); store.refresh()
    #expect(!store.refreshing)
    store.systemDidWake(); store.systemDidWake()
    while store.refreshing { try await Task.sleep(for: .milliseconds(5)) }
    #expect(await count.count == 1)
}
