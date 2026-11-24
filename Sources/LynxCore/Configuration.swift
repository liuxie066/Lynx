import Foundation

public enum Market: String, Codable, CaseIterable, Sendable, Identifiable {
    case us, hk
    public var id: Self { self }
    public var title: String { self == .us ? "美股" : "港股" }
    public var currency: String { self == .us ? "USD" : "HKD" }
    public var openDCode: Int { self == .us ? 11 : 1 }
}

public enum Strategy: String, CaseIterable, Identifiable, Sendable, Codable {
    case csp = "CSP", cc = "CC"
    public var id: Self { self }
    public var title: String { self == .csp ? "现金担保卖出看跌" : "备兑卖出看涨" }
}

// Text preserves incomplete edits. No unverified OM defaults are supplied.
public struct StrategySettings: Codable, Equatable, Sendable {
    public var enabled = false
    public var minStrike = ""
    public var maxStrike = ""
    public var minDTE = ""
    public var maxDTE = ""
    public var maxAbsoluteDelta = ""
    public var advanced: AdvancedSettings?
    public init() {}

    public func validationMessage(for strategy: Strategy) -> String? {
        for (name, text) in [("最低行权价", minStrike), ("最高行权价", maxStrike)] where !text.isEmpty {
            guard let value = Double(text), value.isFinite, value > 0 else { return "\(name)必须大于 0" }
        }
        for (name, text) in [("最短 DTE", minDTE), ("最长 DTE", maxDTE)] where !text.isEmpty {
            guard let value = Int(text), (1...365).contains(value) else { return "\(name)必须为 1–365 的整数" }
        }
        if let low = Double(minStrike), let high = Double(maxStrike), low > high { return "最低行权价不能高于最高行权价" }
        if let low = Int(minDTE), let high = Int(maxDTE), low > high { return "最短 DTE 不能大于最长 DTE" }
        if !maxAbsoluteDelta.isEmpty {
            guard let value = Double(maxAbsoluteDelta), value.isFinite, (0...1).contains(value) else { return "绝对 Delta 必须在 0 到 1 之间" }
        }
        if let error = advanced?.validationMessage { return error }
        if enabled && strategy == .csp && maxStrike.isEmpty { return "待设置：填写最高行权价作为接货上限" }
        return nil
    }
}

public struct WatchStock: Codable, Equatable, Identifiable, Sendable {
    public let market: Market
    public let code: String
    public var csp = StrategySettings()
    public var cc = StrategySettings()
    public var name: String?
    public var id: String { "\(market.rawValue).\(code)" }
    public init(market: Market, code: String) throws {
        let value = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pattern = market == .us ? "^[A-Z][A-Z0-9.-]{0,14}$" : "^[0-9]{1,5}$"
        guard value.range(of: pattern, options: .regularExpression) != nil else {
            throw ConfigurationError.invalidSymbol
        }
        self.market = market
        self.code = market == .hk ? String(repeating: "0", count: 5 - value.count) + value : value
    }
    public subscript(strategy: Strategy) -> StrategySettings {
        get { strategy == .csp ? csp : cc }
        set { if strategy == .csp { csp = newValue } else { cc = newValue } }
    }
}

public struct AppConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion = 1
    public var port: UInt16 = 11111
    public var stocks: [WatchStock] = []
    public var preferences: Preferences?
    public init() {}
}

public enum ConfigurationError: LocalizedError {
    case invalidSymbol, unsupportedVersion, invalidPort, invalidStockList
    public var errorDescription: String? {
        switch self {
        case .invalidSymbol: return "请输入股票代码（美股如 AAPL，港股如 00700）。名称识别尚未接入。"
        case .unsupportedVersion: return "配置版本不受支持，原文件已保留。"
        case .invalidPort: return "端口必须为 1–65535。"
        case .invalidStockList: return "关注列表包含无效或重复代码，原文件已保留。"
        }
    }
}

public struct ConfigurationFile: Sendable {
    public let url: URL
    public init(url: URL) { self.url = url }
    public func load() throws -> AppConfiguration {
        guard FileManager.default.fileExists(atPath: url.path) else { return AppConfiguration() }
        let value = try JSONDecoder().decode(AppConfiguration.self, from: Data(contentsOf: url))
        try validate(value)
        return value
    }
    public func save(_ value: AppConfiguration) throws {
        try validate(value)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }
    public func validate(_ value: AppConfiguration) throws {
        guard value.schemaVersion == 1 else { throw ConfigurationError.unsupportedVersion }
        if let preferences = value.preferences { try preferences.validate() }
        guard value.port > 0 else { throw ConfigurationError.invalidPort }
        var ids = Set<String>()
        for stock in value.stocks {
            guard let canonical = try? WatchStock(market: stock.market, code: stock.code),
                  canonical.code == stock.code, ids.insert(stock.id).inserted else { throw ConfigurationError.invalidStockList }
        }
    }
}
