import Foundation

public struct AdvancedSettings: Codable, Equatable, Sendable {
    public var minAnnualYield = 0.10
    public var minNetPremiumCNY = 50.0
    public var maxSpread = 0.40
    public var minIVRV = 1.10
    public var minIVMinusRV = 0.05
    public init() {}
    public var validationMessage: String? {
        let values = [minAnnualYield, minNetPremiumCNY, maxSpread, minIVRV, minIVMinusRV]
        return values.allSatisfy { $0.isFinite && $0 >= 0 } && maxSpread <= 2 ? nil : "高级参数必须为有效非负数；价差比例不能超过 2"
    }
}

public struct Preferences: Codable, Equatable, Sendable {
    public var refreshMinutes = 0
    public var recommendationNotifications = false
    public var connectionNotifications = false
    public var closeReminderShown = false
    public init() {}
    public func validate() throws {
        guard [0, 10, 30, 60].contains(refreshMinutes) else { throw AnalysisError.message("刷新间隔仅支持关闭、10、30、60 分钟") }
    }
}

public enum AnalysisError: LocalizedError, Sendable {
    case message(String)
    public var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}

public struct EffectivePolicy: Codable, Equatable, Sendable {
    public let minStrike: Double
    public let maxStrike: Double
    public let minDTE: Int
    public let maxDTE: Int
    public let maxDelta: Double
    public let advanced: AdvancedSettings
    public init(settings: StrategySettings, strategy: Strategy, market: Market, spot: Double) throws {
        if let error = settings.validationMessage(for: strategy) { throw AnalysisError.message(error) }
        guard spot.isFinite, spot > 0 else { throw AnalysisError.message("标的现价不可用") }
        if strategy == .csp {
            maxStrike = min(Double(settings.maxStrike) ?? spot, spot)
            minStrike = max(Double(settings.minStrike) ?? 0, maxStrike * 0.80)
        } else {
            minStrike = max(Double(settings.minStrike) ?? spot, spot)
            maxStrike = min(Double(settings.maxStrike) ?? .greatestFiniteMagnitude, minStrike * 1.20)
        }
        minDTE = Int(settings.minDTE) ?? 7
        maxDTE = Int(settings.maxDTE) ?? (market == .us ? 60 : 90)
        maxDelta = Double(settings.maxAbsoluteDelta) ?? 0.40
        advanced = settings.advanced ?? AdvancedSettings()
        guard maxDTE >= minDTE, minDTE > 0, maxDTE <= 365 else { throw AnalysisError.message("DTE 需在 1–365 天内，且下限不超过上限") }
    }
}

public struct OptionEvidence: Codable, Equatable, Sendable, Identifiable {
    public var id: String
    public var stockID: String
    public var strategy: Strategy
    public var expiry: String
    public var dte: Int
    public var spot: Double
    public var strike: Double
    public var multiplier: Int?
    public var bid: Double?
    public var ask: Double?
    public var tick: Double?
    public var openInterest: Int?
    public var delta: Double?
    public var iv: Double?
    public var rv: Double?
    public var cnyRate: Double?
    public var earningsBlocked: Bool?
    public var spotObservedAt: Date?
    public var receivedAt: Date
    public var unavailable: [String]
    public init(id: String, stockID: String, strategy: Strategy, expiry: String, dte: Int, spot: Double, strike: Double,
                multiplier: Int?, bid: Double?, ask: Double?, tick: Double?, openInterest: Int?, delta: Double?,
                iv: Double?, rv: Double?, cnyRate: Double?, earningsBlocked: Bool?, receivedAt: Date, spotObservedAt: Date? = nil, unavailable: [String] = []) {
        self.id = id; self.stockID = stockID; self.strategy = strategy; self.expiry = expiry; self.dte = dte
        self.spot = spot; self.strike = strike; self.multiplier = multiplier; self.bid = bid; self.ask = ask
        self.tick = tick; self.openInterest = openInterest; self.delta = delta; self.iv = iv; self.rv = rv
        self.spotObservedAt = spotObservedAt ?? receivedAt
        self.cnyRate = cnyRate; self.earningsBlocked = earningsBlocked; self.receivedAt = receivedAt; self.unavailable = unavailable
    }
}

public struct Candidate: Codable, Equatable, Sendable, Identifiable {
    public let evidence: OptionEvidence
    public let policy: EffectivePolicy
    public let sellLimit: Double
    public let fee: Double
    public let netPremium: Double
    public let holdingYield: Double
    public let annualYield: Double
    public let distance: Double
    public let collateral: Double
    public let spread: Double
    public var id: String { evidence.id }
    public var explanation: String {
        let direction = evidence.strategy == .csp ? "接货净折价" : "行权价高于现价的比例"
        return "持有期收益率按 0.2 个百分点分档，以档首最高值为锚。档内优先\(evidence.strategy == .csp ? "接货净折价" : "行权价（跨标的用上行比例）")，再比较价差、已知 OI、净权利金和稳定代码。\(direction)：\(String(format: "%.2f%%", distance * 100))。限价按买卖中间价向上对齐最小价位；手续费为估算，以实际账户收费为准。"
    }
}

public struct Evaluation: Sendable {
    public let candidate: Candidate?
    public let reasons: [String]
    public let incomplete: Bool
}

public enum StrategyEngine {
    public static let feeVersion = "futu_option_sell_fee.v1"
    public static func rounded(_ value: Double, digits: Int = 6) -> Double {
        let factor = pow(10, Double(digits)); return (value * factor).rounded(.toNearestOrEven) / factor
    }
    public static func fee(market: Market, premium: Double, shares: Int) -> Double {
        if market == .hk { return rounded(max(premium * Double(shares) * 0.002, 3) + 15 + (premium == 0.01 ? 0 : 3)) }
        return rounded(max(premium > 0.1 ? 0.65 : 0.15, 1.99) + 0.60 + 0.013 + 0.02 + 0.18 + 0.0003
                       + max(premium * Double(shares) * 0.0000206, 0.01) + 0.01)
    }
    public static func evaluate(_ e: OptionEvidence, policy p: EffectivePolicy, market: Market, now: Date) -> Evaluation {
        if e.bid == 0, let ask = e.ask, ask > 0, ask.isFinite {
            return Evaluation(candidate: nil, reasons: ["当前没有有效买价"], incomplete: false)
        }
        var gaps = e.unavailable
        func positive(_ value: Double?) -> Bool { value.map { $0.isFinite && $0 > 0 } ?? false }
        if !positive(e.bid) || !positive(e.ask) || (e.ask ?? 0) < (e.bid ?? 0) { gaps.append("买卖报价缺失、为零或倒挂") }
        if !positive(e.tick) { gaps.append("最小价位缺失") }
        if (e.multiplier ?? 0) <= 0 { gaps.append("真实合约股数缺失或冲突") }
        if !positive(e.iv) || !positive(e.rv) { gaps.append("IV 或期限匹配 RV 不可用") }
        if !positive(e.cnyRate) { gaps.append("CNY 汇率不可用") }
        if e.earningsBlocked == nil { gaps.append("财报日历覆盖不足") }
        if !e.spot.isFinite || e.spot <= 0 || !e.strike.isFinite || e.strike <= 0 || e.dte <= 0 { gaps.append("现价、行权价或期限无效") }
        if let delta = e.delta, delta.isFinite, abs(delta) <= 1,
           (e.strategy == .csp ? delta <= 0 : delta >= 0) {} else { gaps.append("Delta 缺失或符号无效") }
        if let date = e.spotObservedAt, (0...300).contains(now.timeIntervalSince(date)) {} else { gaps.append("标的现价时间缺失或过期") }
        let age = now.timeIntervalSince(e.receivedAt)
        if age < 0 || age > 300 { gaps.append("行情接收时间已过期") }
        guard gaps.isEmpty, let bid = e.bid, let ask = e.ask, let tick = e.tick, let shares = e.multiplier,
              let iv = e.iv, let rv = e.rv, let fx = e.cnyRate, let delta = e.delta else {
            return Evaluation(candidate: nil, reasons: gaps, incomplete: true)
        }
        let mid = (bid + ask) / 2
        var units = Decimal(string: String(mid))! / Decimal(string: String(tick))!
        var ceiling = Decimal()
        NSDecimalRound(&ceiling, &units, 0, .up)
        let limit = NSDecimalNumber(decimal: ceiling * Decimal(string: String(tick))!).doubleValue
        let fees = fee(market: market, premium: limit, shares: shares)
        let net = rounded(limit * Double(shares) - fees)
        let collateral = rounded((e.strategy == .csp ? e.strike : e.spot) * Double(shares))
        let basis = e.strategy == .csp ? collateral - net : collateral
        guard net > 0, basis > 0 else { return Evaluation(candidate: nil, reasons: ["扣费后权利金或收益率基数不为正"], incomplete: false) }
        let holding = rounded(net / basis, digits: 10)
        let annual = rounded(net / basis * 365 / Double(e.dte), digits: 10)
        let spread = rounded((ask - bid) / mid, digits: 10)
        let distance = rounded(e.strategy == .csp ? (e.spot - (e.strike - net / Double(shares))) / e.spot : (e.strike - e.spot) / e.spot, digits: 10)
        var reasons: [String] = []
        if !(p.minDTE...p.maxDTE).contains(e.dte) { reasons.append("DTE 超出 \(p.minDTE)–\(p.maxDTE) 天") }
        if e.strike < p.minStrike || e.strike > p.maxStrike { reasons.append("行权价超出有效区间 \(p.minStrike)–\(p.maxStrike)") }
        if annual < p.advanced.minAnnualYield { reasons.append("年化收益率低于 \(p.advanced.minAnnualYield * 100)%") }
        if rounded(net * fx) < p.advanced.minNetPremiumCNY { reasons.append("每手净权利金低于 \(p.advanced.minNetPremiumCNY) CNY") }
        if spread > p.advanced.maxSpread { reasons.append("买卖价差过大") }
        if abs(delta) > p.maxDelta { reasons.append("绝对 Delta 超过 \(p.maxDelta)") }
        if rounded(iv / rv) < p.advanced.minIVRV { reasons.append("IV/RV 低于 \(p.advanced.minIVRV)") }
        if rounded(iv - rv) < p.advanced.minIVMinusRV { reasons.append("IV−RV 低于 \(p.advanced.minIVMinusRV)") }
        if e.earningsBlocked == true { reasons.append("到期前六天内有尚未公布的财报事件") }
        let candidate = Candidate(evidence: e, policy: p, sellLimit: limit, fee: fees, netPremium: net,
                                  holdingYield: holding, annualYield: annual, distance: distance, collateral: collateral, spread: spread)
        return Evaluation(candidate: reasons.isEmpty ? candidate : nil, reasons: reasons, incomplete: false)
    }
    public static func rank(_ candidates: [Candidate], acrossStocks: Bool = false) -> [Candidate] {
        var remaining = candidates.sorted { $0.holdingYield == $1.holdingYield ? $0.id < $1.id : $0.holdingYield > $1.holdingYield }
        var output: [Candidate] = []
        while let anchor = remaining.first?.holdingYield {
            let count = remaining.prefix { $0.holdingYield >= rounded(anchor - 0.002, digits: 10) }.count
            output += remaining.prefix(count).sorted { a, b in
                let firstA = a.evidence.strategy == .cc && !acrossStocks ? a.evidence.strike : a.distance
                let firstB = b.evidence.strategy == .cc && !acrossStocks ? b.evidence.strike : b.distance
                if firstA != firstB { return firstA > firstB }
                if a.spread != b.spread { return a.spread < b.spread }
                let oiA = a.evidence.openInterest, oiB = b.evidence.openInterest
                if (oiA != nil) != (oiB != nil) { return oiA != nil }
                if let oiA, let oiB, oiA != oiB { return oiA > oiB }
                if a.netPremium != b.netPremium { return a.netPremium > b.netPremium }
                if acrossStocks, a.evidence.stockID != b.evidence.stockID { return a.evidence.stockID < b.evidence.stockID }
                return a.id < b.id
            }
            remaining.removeFirst(count)
        }
        return output
    }
    public static func realizedVolatility(closes: [String: Double], sessions: [String], today: String, expiry: String) -> Double? {
        let ordered = Array(Set(sessions)).sorted()
        let remaining = ordered.filter { $0 >= today && $0 <= expiry }.count
        guard remaining > 0 else { return nil }
        let count = max(20, remaining)
        let required = ordered.filter { $0 < today }.suffix(count + 1)
        guard required.count == count + 1 else { return nil }
        let values = required.compactMap { closes[$0] }.filter { $0.isFinite && $0 > 0 }
        guard values.count == required.count else { return nil }
        let returns = zip(values, values.dropFirst()).map { log($1 / $0) }
        let mean = returns.reduce(0, +) / Double(count)
        let variance = returns.reduce(0) { $0 + pow($1 - mean, 2) } / Double(count - 1)
        let result = rounded(sqrt(variance * 252))
        return result > 0 ? result : nil
    }
}
