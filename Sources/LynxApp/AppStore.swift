import SwiftUI
import AppKit
import UserNotifications
import ServiceManagement
#if canImport(LynxCore)
import LynxCore
#endif

@MainActor final class AppStore: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published var configuration = AppConfiguration()
    @Published var market: Market = .us
    @Published var page: Page? = .options
    @Published var storageError: String?
    @Published var historyError: String?
    @Published var connectionMessage = "尚未检查 OpenD"
    @Published var checking = false
    @Published var lastHandshake: Date?
    @Published var portText = "11111"
    @Published var records: [String: MarketRecord] = [:]
    @Published var refreshing = false
    @Published var progress = ""
    @Published var notificationStatus = "默认关闭"
    @Published var launchAtLogin = false
    @Published var integrationMessage: String?
    let preview: Bool
    let file: ConfigurationFile
    let resultsURL: URL
    private var canSave = true
    private var canSaveResults = true
    private var checkTask: Task<Void, Never>?
    private var refreshTask: Task<Void, Never>?
    private var timerTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var sleeping = false
    private var started = false
    var openMainWindow: (() -> Void)?
    var agentBridge: AgentBridge?
    var scan: @Sendable (UInt16, Market, [WatchStock]) async throws -> ScanOutcome = { port, market, stocks in
        try await BrokerScanner(port: port).scan(market: market, stocks: stocks)
    }

    var resolve: @Sendable (UInt16, Market, String) async throws -> WatchStock = { port, market, query in
        try await BrokerScanner(port: port).resolve(market: market, query: query)
    }

    init(preview: Bool = CommandLine.arguments.contains("--preview"), configurationURL: URL? = nil) {
        self.preview = preview
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let args = CommandLine.arguments
        let overrideIndex = args.firstIndex(of: "--data-directory")
        let override = overrideIndex.flatMap { $0 + 1 < args.count ? URL(fileURLWithPath: args[$0 + 1], isDirectory: true).appendingPathComponent("configuration.json") : nil }
        file = ConfigurationFile(url: configurationURL ?? override ?? support.appendingPathComponent("Lynx/configuration.json"))
        resultsURL = file.url.deletingLastPathComponent().appendingPathComponent("results.json")
        super.init()
        if preview {
            for (market, codes) in [(Market.us, ["AAPL", "NVDA", "TSLA"]), (.hk, ["00700", "09988", "00981"])] {
                for code in codes {
                    if var stock = try? WatchStock(market: market, code: code) {
                        stock.csp.enabled = true; stock.cc.enabled = true
                        configuration.stocks.append(stock)
                    }
                }
            }
        } else {
            do { configuration = try file.load() }
            catch { canSave = false; storageError = "配置无法读取，已保留原文件并暂停保存：\(error.localizedDescription)" }
            if FileManager.default.fileExists(atPath: resultsURL.path) {
                do {
                    let saved = try JSONDecoder().decode(SavedResults.self, from: Data(contentsOf: resultsURL))
                    guard saved.schemaVersion == 1 else { throw ConfigurationError.unsupportedVersion }
                    records = saved.markets
                    for key in records.keys {
                        records[key]?.stale = true
                        records[key]?.message = "历史结果 · 等待刷新"
                        if saved.configuration.port != configuration.port || saved.configuration.stocks != configuration.stocks { records[key]?.invalidate() }
                    }
                } catch { canSaveResults = false; historyError = "历史结果无法读取：\(error.localizedDescription)；已保留原文件" }
            }
        }
        portText = String(configuration.port)
    }
    var preferences: Preferences { configuration.preferences ?? Preferences() }
    var stocks: [WatchStock] { configuration.stocks.filter { $0.market == market } }
    func record(_ market: Market) -> MarketRecord {
        var value = records[market.rawValue] ?? MarketRecord()
        if let date = value.result?.completedAt, Date().timeIntervalSince(date) > 300 { value.stale = true }
        return value
    }

    func start() {
        guard !started, !preview else { return }; started = true
        launchAtLogin = SMAppService.mainApp.status == .enabled
        if Bundle.main.bundleIdentifier != nil {
            UNUserNotificationCenter.current().delegate = self
            if preferences.recommendationNotifications || preferences.connectionNotifications {
                Task {
                    let settings = await UNUserNotificationCenter.current().notificationSettings()
                    notificationStatus = settings.authorizationStatus == .authorized ? "已允许" : "系统尚未授权通知"
                }
            }
        }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.systemWillSleep() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.systemDidWake() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { [weak self] notification in
            guard let window = notification.object as? NSWindow else { return }
            Task { @MainActor in if window.title == "Lynx" { self?.showCloseReminder() } }
        })
        do { agentBridge = try AgentBridge(store: self, directory: file.url.deletingLastPathComponent()) }
        catch { integrationMessage = "本地 Agent 入口无法启动：\(error.localizedDescription)" }
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.objectWillChange.send()
                self?.refresh(manual: false)
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
            }
        }
    }
    func systemWillSleep() { sleeping = true; refreshTask?.cancel(); checkTask?.cancel() }
    func systemDidWake() { sleeping = false; refresh(manual: false) }
    func stop() { refreshTask?.cancel(); checkTask?.cancel(); timerTask?.cancel(); agentBridge?.stop() }
    func showCloseReminder() {
        guard !preferences.closeReminderShown, !preview else { return }
        var pref = preferences; pref.closeReminderShown = true; setPreferences(pref)
        let alert = NSAlert(); alert.messageText = "Lynx 会留在菜单栏"
        alert.informativeText = "关闭窗口后继续按设置刷新。使用菜单栏的“退出 Lynx”可停止 Lynx；OpenD 不受影响。"
        alert.addButton(withTitle: "知道了"); alert.runModal()
    }
    func addStock(code: String) throws { try insertStock(WatchStock(market: market, code: code)) }
    func insertStock(_ stock: WatchStock) throws {
        guard !configuration.stocks.contains(where: { $0.id == stock.id }) else { return }
        configuration.stocks.append(stock); invalidate(stock.market); save()
    }
    func resolveAndAdd(_ query: String, market: Market) async throws -> WatchStock {
        let stock = try await resolve(configuration.port, market, query)
        try Task.checkCancellation()
        try insertStock(stock)
        if let storageError { throw AnalysisError.message(storageError) }
        return stock
    }
    func removeStock(_ id: String) {
        if let stock = configuration.stocks.first(where: { $0.id == id }) {
            configuration.stocks.removeAll { $0.id == id }; invalidate(stock.market); save()
        }
    }
    func settings(stockID: String, strategy: Strategy) -> Binding<StrategySettings> {
        Binding { self.configuration.stocks.first(where: { $0.id == stockID })?[strategy] ?? StrategySettings() }
        set: { value in
            guard let index = self.configuration.stocks.firstIndex(where: { $0.id == stockID }) else { return }
            self.configuration.stocks[index][strategy] = value
            self.invalidate(self.configuration.stocks[index].market); self.save()
        }
    }
    func invalidate(_ market: Market) {
        records[market.rawValue, default: MarketRecord()].invalidate()
        refreshTask?.cancel()
    }
    func savePort() {
        guard let port = UInt16(portText), port > 0, configuration.port != port else { return }
        configuration.port = port; lastHandshake = nil; connectionMessage = "端口已更改，尚未检查"
        cancelCheck(); Market.allCases.forEach(invalidate); save()
    }
    var validPort: Bool { UInt16(portText).map { $0 > 0 } ?? false }
    func save() {
        guard !preview, canSave else { return }
        do { try file.save(configuration); storageError = nil; saveResults() }
        catch { storageError = "配置尚未保存：\(error.localizedDescription)" }
    }
    func saveResults() {
        guard !preview, canSave, canSaveResults else { return }
        do {
            try FileManager.default.createDirectory(at: resultsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(SavedResults(configuration: configuration, markets: records)).write(to: resultsURL, options: .atomic)
        } catch { storageError = "结果尚未保存：\(error.localizedDescription)" }
    }
    func setPreferences(_ value: Preferences) {
        guard (try? value.validate()) != nil else { return }
        let old = preferences
        configuration.preferences = value; save()
        if (!old.recommendationNotifications && value.recommendationNotifications) || (!old.connectionNotifications && value.connectionNotifications) {
            requestNotifications()
        }
    }
    func preference<T>(_ key: WritableKeyPath<Preferences, T>) -> Binding<T> {
        Binding { self.preferences[keyPath: key] } set: { value in var pref = self.preferences; pref[keyPath: key] = value; self.setPreferences(pref) }
    }
    func setLogin(_ enabled: Bool) {
        guard !preview else { return }
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = SMAppService.mainApp.status == .enabled
            if enabled && !launchAtLogin { integrationMessage = "登录启动等待系统设置批准" }
        } catch { integrationMessage = "登录启动未生效：\(error.localizedDescription)" }
    }
    func requestNotifications() {
        guard !preview, Bundle.main.bundleIdentifier != nil else { return }
        Task {
            do { notificationStatus = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) ? "已允许" : "系统未授权；可在系统设置中更改" }
            catch { notificationStatus = "权限申请失败：\(error.localizedDescription)" }
        }
    }
    func notify(_ title: String, market: Market, page: Page) {
        guard !preview, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent(); content.title = title; content.body = "打开 Lynx 查看详情"
        content.userInfo = ["market": market.rawValue, "page": page.rawValue]
        Task {
            do { try await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) }
            catch { notificationStatus = "通知未发送：\(error.localizedDescription)" }
        }
    }
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let market = response.notification.request.content.userInfo["market"] as? String
        let page = response.notification.request.content.userInfo["page"] as? String
        await MainActor.run {
            self.market = market.flatMap(Market.init(rawValue:)) ?? .us
            self.page = page.flatMap(Page.init(rawValue:)) ?? .options
            self.openMainWindow?()
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first(where: { $0.title == "Lynx" })?.makeKeyAndOrderFront(nil)
        }
    }
    func refresh(manual: Bool = true, now: Date = Date()) {
        guard !preview, !sleeping, !refreshing, !checking, canSave else { return }
        let interval = preferences.refreshMinutes
        guard manual || interval > 0 else { return }
        let markets = Market.allCases.filter { market in
            guard configuration.stocks.contains(where: { $0.market == market && ($0.csp.enabled || $0.cc.enabled) }) else { return false }
            return manual || record(market).lastAttempt.map { now.timeIntervalSince($0) >= Double(interval * 60) } ?? true
        }
        guard !markets.isEmpty else { progress = "在配置页启用 CSP 或 CC 后刷新"; return }
        refreshing = true
        let config = configuration
        refreshTask = Task {
            defer { refreshing = false; refreshTask = nil; progress = ""; saveResults() }
            for market in markets {
                if Task.isCancelled { break }
                records[market.rawValue, default: MarketRecord()].lastAttempt = now
                progress = "正在刷新\(market.title)…"
                do {
                    let outcome = try await scan(config.port, market, config.stocks.filter { $0.market == market })
                    try Task.checkCancellation()
                    guard config.port == configuration.port, config.stocks == configuration.stocks else { break }
                    switch outcome {
                    case .closed(let message):
                        records[market.rawValue, default: MarketRecord()].message = message
                        records[market.rawValue]?.stale = true
                        records[market.rawValue]?.faultNotified = false
                    case .result(let result):
                        let changed = records[market.rawValue, default: MarketRecord()].accept(result)
                        if let failure = result.connectionFailure { connectionFailed(failure, market: market) }
                        else { records[market.rawValue]?.faultNotified = false }
                        if preferences.recommendationNotifications {
                            for strategy in changed { notify("\(market.title) \(strategy.rawValue) 前三推荐已变化", market: market, page: .options) }
                        }
                    }
                    connectionMessage = "\(market.title)：\(record(market).message)"
                } catch is CancellationError {
                    records[market.rawValue, default: MarketRecord()].stale = true
                    records[market.rawValue]?.message = "刷新已取消 · 保留历史结果"
                    break
                } catch {
                    connectionFailed(error.localizedDescription, market: market)
                }
            }
        }
    }
    func connectionFailed(_ message: String, market: Market) {
        var value = record(market); value.stale = true; value.message = message
        if preferences.connectionNotifications && !value.faultNotified {
            notify("\(market.title)行情连接异常", market: market, page: .settings); value.faultNotified = true
        }
        records[market.rawValue] = value; connectionMessage = message
    }
    func checkConnection() {
        guard !checking, !refreshing, validPort, !preview else { return }
        savePort(); let port = configuration.port; checking = true; connectionMessage = "正在检查本机 OpenD…"
        checkTask = Task {
            defer { checking = false; checkTask = nil }
            do {
                let report = try await OpenDClient(port: port).probe(timeout: .seconds(8)); try Task.checkCancellation()
                lastHandshake = report.checkedAt; connectionMessage = "握手成功 · OpenD \(report.serverVersion)；刷新将检查行情权限"
            } catch is CancellationError { connectionMessage = "检查已取消" }
            catch { connectionMessage = error.localizedDescription }
        }
    }
    func cancelCheck() { checkTask?.cancel() }
}
