import Foundation

public struct StockResult: Codable, Equatable, Sendable, Identifiable {
    public let stock: WatchStock
    public let strategy: Strategy
    public var candidates: [Candidate] = []
    public var reasons: [String] = []
    public var incomplete = false
    public var id: String { stock.id + "." + strategy.rawValue }
    public init(stock: WatchStock, strategy: Strategy) { self.stock = stock; self.strategy = strategy }
}
public struct MarketResult: Codable, Equatable, Sendable {
    public let market: Market
    public let startedAt: Date
    public var completedAt: Date
    public var stocks: [StockResult]
    public var connectionFailure: String?
    public var complete: Bool { connectionFailure == nil && stocks.allSatisfy { !$0.incomplete } }
    public init(market: Market, startedAt: Date, completedAt: Date, stocks: [StockResult]) {
        self.market = market; self.startedAt = startedAt; self.completedAt = completedAt; self.stocks = stocks
    }
    public mutating func finish(at now: Date) {
        completedAt = now
        for index in stocks.indices {
            let expired = stocks[index].candidates.filter { candidate in
                !(0...300).contains(now.timeIntervalSince(candidate.evidence.receivedAt)) ||
                candidate.evidence.spotObservedAt.map { !(0...300).contains(now.timeIntervalSince($0)) } ?? true
            }
            if !expired.isEmpty {
                let ids = Set(expired.map(\.id))
                stocks[index].candidates.removeAll { ids.contains($0.id) }
                stocks[index].incomplete = true
                stocks[index].reasons.append("部分行情在扫描完成前已过期；请收窄期限或减少同时关注的股票")
            }
        }
    }
    public func representatives(_ strategy: Strategy) -> [Candidate] {
        StrategyEngine.rank(stocks.filter { $0.strategy == strategy }.compactMap { $0.candidates.first }, acrossStocks: true)
    }
    public func top(_ strategy: Strategy) -> [String] { Array(representatives(strategy).prefix(3).map(\.id)) }
}
public enum ScanOutcome: Sendable {
    case closed(String)
    case result(MarketResult)
}
public struct MarketRecord: Codable, Equatable, Sendable {
    public var result: MarketResult?
    public var lastAttempt: Date?
    public var lastSuccess: Date?
    public var message = "尚未刷新"
    public var stale = true
    public var baseline: [String: [String]] = [:]
    public var changes: [String: String] = [:]
    public var previousRanking: [String: [String]]?
    public var faultNotified = false
    public init() {}
    public mutating func accept(_ result: MarketResult) -> [Strategy] {
        self.result = result
        stale = !result.complete
        guard result.complete else { message = "数据不完整 · 查看各标的原因"; return [] }
        lastSuccess = result.completedAt
        message = "刷新成功"
        faultNotified = false
        var changed: [Strategy] = []
        for strategy in Strategy.allCases {
            let new = result.top(strategy)
            let old = baseline[strategy.rawValue]
            if let old, old != new { changed.append(strategy) }
            let previous = previousRanking?[strategy.rawValue] ?? old ?? []
            let all = result.representatives(strategy).map(\.id)
            for (index, id) in all.enumerated() {
                if let before = previous.firstIndex(of: id) {
                    let delta = before - index
                    changes[id] = delta == 0 ? "持平" : delta > 0 ? "上升 \(delta) 位" : "下降 \(-delta) 位"
                } else { changes[id] = "新增" }
            }
            baseline[strategy.rawValue] = new
            if previousRanking == nil { previousRanking = [:] }
            previousRanking?[strategy.rawValue] = all
        }
        return changed
    }
    public mutating func invalidate() { stale = true; baseline = [:]; previousRanking = [:]; changes = [:]; message = "设置已变更 · 等待刷新" }
}
public struct SavedResults: Codable, Sendable {
    public var schemaVersion = 1
    public var configuration: AppConfiguration
    public var markets: [String: MarketRecord]
    public init(configuration: AppConfiguration, markets: [String: MarketRecord]) { self.configuration = configuration; self.markets = markets }
}
public enum MarketDate {
    public static func formatter(_ market: Market, format: String = "yyyy-MM-dd") -> DateFormatter {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: market == .us ? "America/New_York" : "Asia/Hong_Kong"); f.dateFormat = format
        f.isLenient = false; return f
    }
    public static func day(_ date: Date, market: Market) -> String { formatter(market).string(from: date) }
    public static func adding(_ days: Int, to day: String, market: Market) -> String? {
        let f = formatter(market); guard let date = f.date(from: day) else { return nil }
        var c = Calendar(identifier: .gregorian); c.timeZone = f.timeZone
        return c.date(byAdding: .day, value: days, to: date).map(f.string(from:))
    }
    public static func distance(from start: String, to end: String, market: Market) -> Int? {
        let f = formatter(market); guard let a = f.date(from: start), let b = f.date(from: end) else { return nil }
        var c = Calendar(identifier: .gregorian); c.timeZone = f.timeZone
        return c.dateComponents([.day], from: a, to: b).day
    }
}
