import Foundation
import Testing
@testable import LynxCore

struct Golden: Decodable {
    let strategy: Strategy; let market: Market; let shares: Int
    let spot, strike, bid, ask, tick, fee, net, holding, annual, distance, limit: Double
}
func evidence(strategy: Strategy = .csp, id: String = "us.TEST1", shares: Int? = 50) -> OptionEvidence {
    OptionEvidence(id: id, stockID: "us.TEST", strategy: strategy, expiry: "2026-12-08", dte: 14,
                   spot: 100, strike: strategy == .csp ? 95 : 105, multiplier: shares, bid: 2.01, ask: 2.12,
                   tick: 0.05, openInterest: 0, delta: strategy == .csp ? -0.3 : 0.3, iv: 0.4, rv: 0.2,
                   cnyRate: 7, earningsBlocked: false, receivedAt: Date())
}
func policy(strategy: Strategy = .csp, market: Market = .us) throws -> EffectivePolicy {
    var settings = StrategySettings(); settings.enabled = true; settings.maxStrike = strategy == .csp ? "100" : ""
    return try EffectivePolicy(settings: settings, strategy: strategy, market: market, spot: 100)
}
@Test func fixedInputsMatchOMGoldenMetrics() throws {
    let rows = try JSONDecoder().decode([Golden].self, from: Data(contentsOf: Bundle.module.url(forResource: "om-metrics", withExtension: "json")!))
    for row in rows {
        var e = evidence(strategy: row.strategy, shares: row.shares)
        e.bid = row.bid; e.ask = row.ask; e.tick = row.tick; e.cnyRate = row.market == .us ? 7 : 0.9
        let result = StrategyEngine.evaluate(e, policy: try policy(strategy: row.strategy, market: row.market), market: row.market, now: Date())
        let c = try #require(result.candidate)
        #expect(abs(c.fee - row.fee) < 1e-6)
        #expect(abs(c.netPremium - row.net) < 1e-6)
        #expect(abs(c.sellLimit - row.limit) < 1e-9)
        #expect(abs(c.holdingYield - row.holding) < 1e-10)
        #expect(abs(c.annualYield - row.annual) < 1e-10)
        #expect(abs(c.distance - row.distance) < 1e-10)
        #expect(c.collateral == row.strike * Double(row.shares) || row.strategy == .cc)
    }
}
@Test func unknownMultiplierRVAndEarningsNeverBecomeZeroOrRecommendation() throws {
    let p = try policy()
    var e = evidence(shares: nil)
    #expect(StrategyEngine.evaluate(e, policy: p, market: .us, now: Date()).incomplete)
    e = evidence(); e.rv = nil
    #expect(StrategyEngine.evaluate(e, policy: p, market: .us, now: Date()).candidate == nil)
    e = evidence(); e.earningsBlocked = nil
    #expect(StrategyEngine.evaluate(e, policy: p, market: .us, now: Date()).incomplete)
    e = evidence(); e.earningsBlocked = true
    let blocked = StrategyEngine.evaluate(e, policy: p, market: .us, now: Date())
    #expect(blocked.candidate == nil && !blocked.incomplete)
    e = evidence(); e.bid = 0
    #expect(!StrategyEngine.evaluate(e, policy: p, market: .us, now: Date()).incomplete)
    e = evidence(); e.delta = 0.3
    #expect(StrategyEngine.evaluate(e, policy: p, market: .us, now: Date()).incomplete)
}
func rankedCandidate(_ id: String, yield: Double, distance: Double, strike: Double = 100, oi: Int? = 0, strategy: Strategy = .csp) throws -> Candidate {
    var e = evidence(strategy: strategy, id: id); e.strike = strike; e.openInterest = oi; e.stockID = id
    return Candidate(evidence: e, policy: try policy(strategy: strategy), sellLimit: 2, fee: 3, netPremium: 97,
                     holdingYield: yield, annualYield: yield, distance: distance, collateral: 5000, spread: 0.1)
}
@Test func returnBandsAnchorAtMaximumAndBoundaryIsInclusive() throws {
    let a = try rankedCandidate("a", yield: 0.020, distance: 0.01)
    let b = try rankedCandidate("b", yield: 0.018, distance: 0.02)
    let c = try rankedCandidate("c", yield: 0.0165, distance: 0.99)
    #expect(StrategyEngine.rank([c, a, b]).map(\.id) == ["b", "a", "c"])
}
@Test func crossStockCCUsesPercentageAndKnownOIBeatsUnknown() throws {
    let a = try rankedCandidate("a", yield: 0.02, distance: 0.01, strike: 500, strategy: .cc)
    let b = try rankedCandidate("b", yield: 0.02, distance: 0.08, strike: 100, strategy: .cc)
    #expect(StrategyEngine.rank([a,b]).first?.id == "a")
    #expect(StrategyEngine.rank([a,b], acrossStocks: true).first?.id == "b")
    let unknown = try rankedCandidate("a", yield: 0.02, distance: 0.1, oi: nil)
    let zero = try rankedCandidate("z", yield: 0.02, distance: 0.1, oi: 0)
    #expect(StrategyEngine.rank([unknown,zero]).first?.id == "z")
}
@Test func rvRequiresEveryCompletedSessionAndExcludesToday() {
    let sessions = (1...31).map { String(format: "2026-10-%02d", $0) }
    var closes = Dictionary(uniqueKeysWithValues: sessions.map { ($0, 100 + Double(Int($0.suffix(2))!) * (Int($0.suffix(2))! % 2 == 0 ? 0.4 : 0.1)) })
    let rv = StrategyEngine.realizedVolatility(closes: closes, sessions: sessions, today: "2026-10-25", expiry: "2026-10-30")
    #expect(rv != nil)
    closes["2026-10-25"] = 100000
    #expect(StrategyEngine.realizedVolatility(closes: closes, sessions: sessions, today: "2026-10-25", expiry: "2026-10-30") == rv)
    closes.removeValue(forKey: "2026-10-20")
    #expect(StrategyEngine.realizedVolatility(closes: closes, sessions: sessions, today: "2026-10-25", expiry: "2026-10-30") == nil)
}
@Test func marketDatesRespectDSTAndHKPadding() throws {
    #expect(MarketDate.distance(from: "2026-03-07", to: "2026-03-09", market: .us) == 2)
    #expect(try WatchStock(market: .hk, code: "700").code == "00700")
    #expect(try policy(market: .us).maxDTE == 60)
    #expect(try policy(market: .hk).maxDTE == 90)
}
@Test func notificationsIgnorePricesAndIncompleteResultsAndResetOnConfigurationChange() throws {
    let stock = try WatchStock(market: .us, code: "TEST")
    var row = StockResult(stock: stock, strategy: .csp)
    row.candidates = [try rankedCandidate("a", yield: 0.02, distance: 0.1)]
    var result = MarketResult(market: .us, startedAt: Date(), completedAt: Date(), stocks: [row])
    var record = MarketRecord()
    #expect(record.accept(result).isEmpty)
    result.stocks[0].candidates = [try rankedCandidate("a", yield: 0.03, distance: 0.2)]
    #expect(record.accept(result).isEmpty)
    result.stocks[0].incomplete = true; result.stocks[0].candidates = []
    #expect(record.accept(result).isEmpty)
    #expect(record.baseline["CSP"] == ["a"])
    result.stocks[0].incomplete = false
    #expect(record.accept(result) == [.csp])
    record.invalidate()
    #expect(record.accept(result).isEmpty)
}
@Test func fxRejectsWrongPairMissingTimeAndStaleSessions() throws {
    let now = try #require(MarketDate.formatter(.hk, format: "yyyyMMddHHmmss").date(from: "20261124160000"))
    let fresh = "v_whUSDCNY=\"x~x~USDCNY~7.2~x~20261124150000\";"
    #expect(ExchangeRates.parse(fresh, now: now)[.us] == 7.2)
    #expect(ExchangeRates.parse(fresh.replacingOccurrences(of: "20261124150000", with: "20261120150000"), now: now).isEmpty)
    #expect(ExchangeRates.parse(fresh.replacingOccurrences(of: "~USDCNY~", with: "~EURCNY~"), now: now).isEmpty)
}
@Test func hkOfficialFutureCalendarRequiresProviderAgreement() {
    let calendar = HKCalendar.schedule2027()
    #expect(calendar["2027-02-08"] == nil)
    #expect(calendar["2027-02-05"] == 1)
    #expect(calendar["2027-01-04"] == 0)
    #expect(HKCalendar.agrees(provider: [:], schedule: calendar))
    #expect(!HKCalendar.agrees(provider: ["2027-02-08":0], schedule: calendar))
    #expect(!HKCalendar.agrees(provider: ["2027-02-05":0], schedule: calendar))
}
@Test func scanCompletionRechecksQuoteAndSpotFreshness() throws {
    var row = StockResult(stock: try WatchStock(market: .us, code: "TEST"), strategy: .csp)
    row.candidates = [try rankedCandidate("a", yield: 0.02, distance: 0.1)]
    var result = MarketResult(market: .us, startedAt: Date(), completedAt: Date(), stocks: [row])
    result.finish(at: Date().addingTimeInterval(301))
    #expect(!result.complete)
    #expect(result.stocks[0].candidates.isEmpty)
    #expect(!result.stocks[0].reasons.isEmpty)
}
