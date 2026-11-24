import Foundation
#if canImport(LynxCore)
import LynxCore
#endif

@MainActor final class AgentBridge {
    private var server: AgentServer?
    init(store: AppStore, directory: URL) throws {
        server = try AgentServer { [weak store] data in
            await store?.agentHandle(data) ?? Data(#"{"ok":false,"error":"App unavailable"}"#.utf8)
        }
    }
    func stop() { server?.stop(); server = nil }
}

extension AppStore {
    func agentHandle(_ data: Data) async -> Data {
        do {
            let request = try JSONDecoder().decode(AgentRequest.self, from: data)
            let value = try await agentExecute(request)
            return try JSONSerialization.data(withJSONObject: ["ok": true, "data": value], options: [.prettyPrinted, .sortedKeys])
        } catch {
            return (try? JSONSerialization.data(withJSONObject: ["ok": false, "error": error.localizedDescription, "effectiveConfiguration": (try? object(configuration)) ?? [:], "loginAtStartup": launchAtLogin], options: [.prettyPrinted])) ?? Data()
        }
    }
    private func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) }
    private func agentExecute(_ request: AgentRequest) async throws -> Any {
        let args = request.arguments
        let known = ["list", "status", "recommendations", "explain", "watch.add", "watch.remove", "strategy.set", "strategy.reset", "settings.set", "refresh"]
        guard known.contains(request.command) else { throw AnalysisError.message("未知能力；调用 list 查看工具。不支持账户、交易或修改费用。") }
        func required(_ key: String) throws -> String {
            guard let value = args[key], !value.isEmpty else { throw AnalysisError.message("缺少参数 \(key)") }; return value
        }
        func targetMarket() throws -> Market {
            guard let market = Market(rawValue: try required("market")) else { throw AnalysisError.message("market 仅支持 us / hk") }; return market
        }
        func boolean(_ text: String) throws -> Bool {
            guard ["true", "false"].contains(text) else { throw AnalysisError.message("布尔参数需为 true / false") }; return text == "true"
        }
        switch request.command {
        case "list": return ["commands": known, "format": "command + arguments (string values)", "scope": "本地行情分析；不读取账户、持仓或交易；名称解析是 watch.add 的内部步骤"]
        case "status": return ["refreshing": refreshing, "progress": progress, "connection": connectionMessage, "configuration": try object(configuration), "markets": try object(Dictionary(uniqueKeysWithValues: Market.allCases.map { ($0.rawValue, record($0)) })), "loginAtStartup": launchAtLogin, "notificationStatus": notificationStatus] as [String: Any]
        case "recommendations", "explain":
            let market = try targetMarket(), record = record(market)
            var result: [String: Any] = ["market": market.rawValue, "stale": record.stale, "status": record.message, "simulation": true]
            if let snapshot = record.result {
                let direction = args["strategy"].flatMap(Strategy.init(rawValue:))
                if args["strategy"] != nil && direction == nil { throw AnalysisError.message("strategy 仅支持 CSP / CC") }
                let rows = snapshot.stocks.filter { (args["symbol"] == nil || $0.stock.code == args["symbol"]?.uppercased()) && (direction == nil || $0.strategy == direction) }
                result["result"] = try object(rows); result["completedAt"] = snapshot.completedAt.ISO8601Format(); result["complete"] = snapshot.complete
                result["ranking"] = Dictionary(uniqueKeysWithValues: Strategy.allCases.map { ($0.rawValue, snapshot.representatives($0).map(\.id)) })
                result["top"] = Dictionary(uniqueKeysWithValues: Strategy.allCases.map { ($0.rawValue, snapshot.top($0)) })
                result["explanation"] = rows.flatMap { $0.candidates.map { ["contract": $0.id, "explanation": $0.explanation] } }
            }
            return result
        case "refresh":
            guard !preview else { throw AnalysisError.message("预览模式不能刷新") }
            let already = refreshing; refresh()
            return ["running": refreshing, "sharedExistingTask": already, "message": refreshing ? "查看 status 跟踪结果；启动不等于成功" : progress] as [String: Any]
        case "watch.add":
            let stock = try await resolveAndAdd(try required("symbol"), market: try targetMarket()); return try object(stock)
        case "watch.remove":
            let stock = try WatchStock(market: try targetMarket(), code: try required("symbol"))
            removeStock(stock.id)
        case "strategy.set", "strategy.reset":
            let stock = try WatchStock(market: try targetMarket(), code: try required("symbol"))
            guard let index = configuration.stocks.firstIndex(where: { $0.id == stock.id }), let strategy = Strategy(rawValue: try required("strategy")) else { throw AnalysisError.message("关注股票或策略不存在") }
            var setting = configuration.stocks[index][strategy]
            if request.command == "strategy.reset" {
                let enabled = setting.enabled, max = setting.maxStrike
                setting = StrategySettings(); setting.enabled = enabled; if strategy == .csp { setting.maxStrike = max }
            } else {
                let allowed = Set(["market", "symbol", "strategy", "enabled", "minStrike", "maxStrike", "minDTE", "maxDTE", "maxAbsoluteDelta", "minAnnualYield", "minNetPremiumCNY", "maxSpread", "minIVRV", "minIVMinusRV"])
                guard Set(args.keys).isSubset(of: allowed) else { throw AnalysisError.message("不支持的策略参数") }
                if let value = args["enabled"] { setting.enabled = try boolean(value) }
                if let value = args["minStrike"] { setting.minStrike = value }; if let value = args["maxStrike"] { setting.maxStrike = value }
                if let value = args["minDTE"] { setting.minDTE = value }; if let value = args["maxDTE"] { setting.maxDTE = value }
                if let value = args["maxAbsoluteDelta"] { setting.maxAbsoluteDelta = value }
                var advanced = setting.advanced ?? AdvancedSettings()
                for (name, key) in [("minAnnualYield", \AdvancedSettings.minAnnualYield), ("minNetPremiumCNY", \.minNetPremiumCNY), ("maxSpread", \.maxSpread), ("minIVRV", \.minIVRV), ("minIVMinusRV", \.minIVMinusRV)] {
                    if let text = args[name] { guard let value = Double(text) else { throw AnalysisError.message("\(name) 必须为数字") }; advanced[keyPath: key] = value }
                }
                setting.advanced = advanced
            }
            if let error = setting.validationMessage(for: strategy) { throw AnalysisError.message(error) }
            settings(stockID: stock.id, strategy: strategy).wrappedValue = setting
        case "settings.set":
            let allowed = Set(["port", "refreshMinutes", "recommendationNotifications", "connectionNotifications", "launchAtLogin"])
            guard Set(args.keys).isSubset(of: allowed) else { throw AnalysisError.message("不支持的设置；费用不可更改") }
            var pref = preferences
            if let text = args["refreshMinutes"] { guard let value = Int(text) else { throw AnalysisError.message("刷新间隔需为整数") }; pref.refreshMinutes = value }
            if let text = args["recommendationNotifications"] { pref.recommendationNotifications = try boolean(text) }
            if let text = args["connectionNotifications"] { pref.connectionNotifications = try boolean(text) }
            try pref.validate()
            if let text = args["port"] { guard let port = UInt16(text), port > 0 else { throw ConfigurationError.invalidPort } }
            let login = try args["launchAtLogin"].map(boolean)
            if let text = args["port"] { portText = text; savePort() }
            setPreferences(pref)
            if let login { setLogin(login); if launchAtLogin != login { throw AnalysisError.message(integrationMessage ?? "登录启动尚未生效") } }
        default: break
        }
        if let storageError { throw AnalysisError.message(storageError) }
        return ["configuration": try object(configuration), "loginAtStartup": launchAtLogin, "message": integrationMessage ?? "已保存"] as [String: Any]
    }
}

enum AgentSkill: String, CaseIterable {
    case codex = "Codex", claude = "Claude Code"
    var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(self == .codex ? ".agents/skills/lynx" : ".claude/skills/lynx")
    }
    var installed: Bool {
        (try? String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8))?.contains("<!-- managed-by-lynx-v1 -->") == true
    }
    var installationStatus: String {
        if installed {
            let content = (try? String(contentsOf: folder.appendingPathComponent("SKILL.md"), encoding: .utf8)) ?? ""
            return content.contains(Bundle.main.executableURL?.path ?? "\0") ? "Lynx 技能已安装 · v1" : "技能已安装 · App 位置变化，请更新"
        }
        return FileManager.default.fileExists(atPath: folder.path) ? "同名目录已占用，未覆盖" : "尚未安装 Lynx 技能"
    }
    var clientStatus: String {
        let name = self == .codex ? "codex" : "claude"
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").components(separatedBy: ":") + [home + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin"]
        return paths.filter { !$0.isEmpty }.contains { FileManager.default.isExecutableFile(atPath: $0 + "/" + name) }
            ? "已检测到客户端 CLI；登录状态由客户端管理" : "未在标准路径检测到客户端 CLI；请自行安装并登录"
    }
    func install(executable: URL, targetFolder: URL? = nil) throws {
        let folder = targetFolder ?? self.folder
        let marker = "<!-- managed-by-lynx-v1 -->"
        let path = folder.appendingPathComponent("SKILL.md")
        if FileManager.default.fileExists(atPath: folder.path) {
            guard let text = try? String(contentsOf: path, encoding: .utf8), text.contains(marker) else { throw AnalysisError.message("同名技能目录已存在，未覆盖；请先检查该目录") }
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let quoted = "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let text = """
        ---
        name: lynx
        description: View and configure the running Lynx macOS options monitor. Use for Lynx recommendations, explanations, watch stocks, strategy settings and refresh.
        ---
        \(marker)
        # Lynx
        Use the running App's local command entry; do not edit its saved files or recalculate recommendations.
        Executable: \(quoted)
        Call: \(quoted) --agent '{"command":"status","arguments":{}}'
        First call list to discover capabilities. JSON argument values are strings. Market is us/hk; strategy CSP/CC.
        Read: status, recommendations, explain (market; optional strategy/symbol). Results include timestamps, stale/complete and simulation flags; never describe incomplete or historical data as current recommendations.
        Writes require explicit user intent: watch.add/watch.remove (market,symbol); strategy.set (market,symbol,strategy plus enabled,minStrike,maxStrike,minDTE,maxDTE,maxAbsoluteDelta,minAnnualYield,minNetPremiumCNY,maxSpread,minIVRV,minIVMinusRV); strategy.reset preserves enabled and CSP acceptance ceiling. watch.add resolves names internally; ambiguity returns choices. settings.set accepts port,refreshMinutes (0/10/30/60),recommendationNotifications,connectionNotifications,launchAtLogin. Boolean strings are true/false. Do not batch unrelated user changes.
        refresh shares the App task; running is not success. Check status afterward. Every write returns effective configuration; verify it. If a write times out, its result is unknown: inspect status before deciding whether to retry. Notification/startup permission remains a macOS prompt, never bypass it.
        No accounts, cash, holdings, ledger, orders, fees editing, temporary option queries or OpenD process management. App must be running. Do not install Python or other runtimes. Restart the Agent session after skill installation/update if it is not discovered.
        """
        try text.write(to: path, atomically: true, encoding: .utf8)
    }
    func uninstall(targetFolder: URL? = nil) throws {
        let folder = targetFolder ?? self.folder
        let path = folder.appendingPathComponent("SKILL.md")
        guard let text = try? String(contentsOf: path, encoding: .utf8), text.contains("<!-- managed-by-lynx-v1 -->") else { throw AnalysisError.message("该技能不是 Lynx 管理的文件，未删除") }
        try FileManager.default.removeItem(at: path)
        if (try FileManager.default.contentsOfDirectory(atPath: folder.path)).isEmpty { try FileManager.default.removeItem(at: folder) }
    }
}
