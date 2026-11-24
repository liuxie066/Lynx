import Foundation

public struct BrokerScanner: Sendable {
    public let port: UInt16
    public init(port: UInt16) { self.port = port }
    public func scan(market: Market, stocks: [WatchStock]) async throws -> ScanOutcome {
        // FX is only requested after the broker proves the regular market is open.
        let state = try await worker { try BrokerSession(port: port).marketOpen(market) }
        guard state else { return .closed("休市 · 保留历史结果") }
        let rates = (try? await ExchangeRates.fetch()) ?? [:]
        return try await worker { try BrokerSession(port: port).scan(market: market, stocks: stocks, fx: rates[market]) }
    }
    public func resolve(market: Market, query: String) async throws -> WatchStock {
        try await worker { try BrokerSession(port: port).resolve(market: market, query: query) }
    }
    private func worker<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        let task = Task.detached(operation: operation)
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
}

private struct MarketStateReply: Decodable {
    struct Item: Decodable { let security: QuoteSecurity; let marketState: Int }
    let marketInfoList: [Item]?
}
private struct CalendarRequest: Encodable { let market: Int; let beginTime: String; let endTime: String }
private struct CalendarReply: Decodable {
    struct Day: Decodable { let time: String; let tradeDateType: Int? }
    let tradeDateList: [Day]?
}
private struct HistoryRequest: Encodable {
    let rehabType = 1; let klType = 2; let security: QuoteSecurity; let beginTime: String; let endTime: String
    let maxAckKLNum = 1000; let nextReqKey: String?
}
private struct HistoryReply: Decodable {
    struct Bar: Decodable { let time: String; let isBlank: Bool; let closePrice: Double? }
    let security: QuoteSecurity; let klList: [Bar]?; let nextReqKey: String?
}
private struct EarningsRequest: Encodable { let market: Int; let beginDate: String; let endDate: String }
private struct EarningsReply: Decodable {
    struct Item: Decodable { let security: QuoteSecurity; let earningsDate: String? }
    let itemList: [Item]?
}
private struct StaticRequest: Encodable { let market: Int?; let secType: Int?; let securityList: [QuoteSecurity]? }
private struct StaticReply: Decodable { let staticInfoList: [ChainReply.StaticInfo]? }

private final class BrokerSession {
    let session: OpenDSession
    var calls: [UInt32: Date] = [:]
    var lastKeepAlive = Date()
    var connectionFailure: String?
    init(port: UInt16) throws {
        session = try OpenDSession(port: port, timeout: .seconds(20))
        let handshake: HandshakeReply = try session.request(.initialize, HandshakeRequest())
        guard handshake.serverVer > 0 else { throw OpenDError.invalidResponse }
    }
    func request<I: Encodable, O: Decodable>(_ proto: QuoteProtocol, _ input: I) throws -> O {
        // Conservative per-protocol pacing, including snapshot batches. Wait remains cancellable.
        let interval = proto == .chain || proto == .earnings ? 3.1 : 1.1
        if let last = calls[proto.rawValue] {
            while Date().timeIntervalSince(last) < interval { try Task.checkCancellation(); Thread.sleep(forTimeInterval: 0.05) }
        }
        try Task.checkCancellation()
        session.socket.resetDeadline(timeout: .seconds(15))
        if Date().timeIntervalSince(lastKeepAlive) >= 8 {
            let _: EmptyReply = try session.request(.keepAlive, KeepAliveRequest(time: String(Int(Date().timeIntervalSince1970))))
            lastKeepAlive = Date()
        }
        calls[proto.rawValue] = Date()
        session.socket.resetDeadline(timeout: .seconds(15))
        do { return try session.request(proto, input) }
        catch let error as OpenDError {
            switch error { case .transport, .closed, .timeout: connectionFailure = error.localizedDescription; default: break }
            throw error
        }
    }
    func marketOpen(_ market: Market) throws -> Bool {
        let security = QuoteSecurity(market: market.openDCode, code: market == .us ? "AAPL" : "00700")
        let reply: MarketStateReply = try request(.marketState, SnapshotRequest(securityList: [security]))
        guard let state = reply.marketInfoList?.first(where: { $0.security == security })?.marketState, state != 0 else {
            throw AnalysisError.message("市场开休市状态不可用")
        }
        return state == 3 || state == 5
    }
    func resolve(market: Market, query: String) throws -> WatchStock {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw AnalysisError.message("股票名称或代码不能为空") }
        if let stock = try? WatchStock(market: market, code: trimmed) {
            do {
                let reply: StaticReply = try request(.staticInfo, StaticRequest(market: nil, secType: nil, securityList: [QuoteSecurity(market: market.openDCode, code: stock.code)]))
                if let item = reply.staticInfoList?.first(where: { $0.basic.security.code == stock.code }), [3, 4].contains(item.basic.secType ?? 0) {
                    var result = stock; result.name = item.basic.name; return result
                }
            } catch OpenDError.rejected { /* Could be a name, continue with the market directory. */ }
        }
        let reply: StaticReply = try request(.staticInfo, StaticRequest(market: market.openDCode, secType: 3, securityList: nil))
        let all = reply.staticInfoList ?? []
        let exact = all.filter { $0.basic.name?.localizedCaseInsensitiveCompare(trimmed) == .orderedSame }
        let matches = exact.isEmpty ? all.filter { $0.basic.name?.localizedCaseInsensitiveContains(trimmed) == true } : exact
        guard matches.count == 1, let item = matches.first else {
            let choices = matches.prefix(8).map { "\($0.basic.security.code) \($0.basic.name ?? "")" }.joined(separator: "、")
            throw AnalysisError.message(matches.isEmpty ? "未识别该名称，请输入股票代码" : "名称有多个匹配，请选择代码：\(choices)")
        }
        var stock = try WatchStock(market: market, code: item.basic.security.code); stock.name = item.basic.name; return stock
    }
    func scan(market: Market, stocks: [WatchStock], fx: Double?) throws -> ScanOutcome {
        let start = Date(), today = MarketDate.day(start, market: market)
        guard try marketOpen(market) else { return .closed("休市 · 保留历史结果") }
        var results: [StockResult] = []
        for stock in stocks where stock.market == market {
            try Task.checkCancellation()
            let enabled = Strategy.allCases.filter { stock[$0].enabled }
            guard !enabled.isEmpty else { continue }
            do { results += try scanStock(stock, enabled: enabled, today: today, fx: fx) }
            catch is CancellationError { throw CancellationError() }
            catch {
                results += enabled.map { direction in
                    var result = StockResult(stock: stock, strategy: direction)
                    result.incomplete = true; result.reasons = [error.localizedDescription]; return result
                }
            }
        }
        var result = MarketResult(market: market, startedAt: start, completedAt: Date(), stocks: results)
        result.connectionFailure = connectionFailure
        result.finish(at: Date())
        return .result(result)
    }
    func scanStock(_ stock: WatchStock, enabled: [Strategy], today: String, fx: Double?) throws -> [StockResult] {
        let owner = QuoteSecurity(market: stock.market.openDCode, code: stock.code)
        var results = enabled.map { StockResult(stock: stock, strategy: $0) }
        for i in results.indices {
            if let error = stock[results[i].strategy].validationMessage(for: results[i].strategy) { results[i].reasons = [error] }
        }
        guard results.contains(where: { $0.reasons.isEmpty }) else { return results }
        let spotReply: SnapshotReply = try request(.snapshot, SnapshotRequest(securityList: [owner]))
        guard let spotQuote = spotReply.snapshotList?.first(where: { $0.basic.security == owner }),
              let spot = spotQuote.basic.curPrice, spot > 0, spotQuote.basic.secStatus == 1, spotQuote.basic.isSuspend == false,
              let observed = spotQuote.basic.updateTime.flatMap({ MarketDate.formatter(stock.market, format: "yyyy-MM-dd HH:mm:ss").date(from: $0) }),
              (0...300).contains(Date().timeIntervalSince(observed)) else { throw AnalysisError.message("标的现价缺失、过期、停牌或状态未知") }
        let expiries: ExpiryReply = try request(.expiration, OwnerRequest(owner: owner))
        let dates = Array(Set((expiries.dateList ?? []).compactMap(\.strikeTime))).sorted()
        var policies: [Strategy: EffectivePolicy] = [:]
        for i in results.indices where results[i].reasons.isEmpty {
            do { policies[results[i].strategy] = try EffectivePolicy(settings: stock[results[i].strategy], strategy: results[i].strategy, market: stock.market, spot: spot) }
            catch { results[i].reasons = [error.localizedDescription] }
        }
        let selected = dates.filter { expiry in
            guard let dte = MarketDate.distance(from: today, to: expiry, market: stock.market) else { return false }
            return policies.values.contains { ($0.minDTE...$0.maxDTE).contains(dte) }
        }
        guard let last = selected.last else {
            for i in results.indices where results[i].reasons.isEmpty { results[i].reasons = ["配置期限内没有期权到期日"] }; return results
        }
        let firstHistory = MarketDate.adding(-400, to: today, market: stock.market)!
        var calendarEnd = min(last, String(today.prefix(4)) + "-12-31")
        var sessions: [String] = [], closes: [String: Double] = [:], historyError: String?
        do {
            let calendar: CalendarReply = try request(.calendar, CalendarRequest(market: stock.market == .us ? 2 : 1, beginTime: firstHistory, endTime: calendarEnd))
            guard let days = calendar.tradeDateList, !days.isEmpty, days.allSatisfy({ [0,1,2].contains($0.tradeDateType ?? -1) }) else { throw AnalysisError.message("交易日历缺失或类型未知") }
            sessions = days.map { String($0.time.prefix(10)) }
            if stock.market == .hk, today.hasPrefix("2026-"), last > "2026-12-31" {
                let end = min(last, "2027-12-31")
                let future: CalendarReply = try request(.calendar, CalendarRequest(market: 1, beginTime: "2027-01-01", endTime: end))
                let official = HKCalendar.schedule2027()
                var observed: [String: Int] = [:]
                for day in future.tradeDateList ?? [] {
                    let date = String(day.time.prefix(10))
                    guard date >= "2027-01-01", date <= end, let type = day.tradeDateType, observed[date] == nil else { throw AnalysisError.message("未来交易日历格式冲突") }
                    observed[date] = type
                }
                guard HKCalendar.agrees(provider: observed, schedule: official) else { throw AnalysisError.message("OpenD 与已核验的 HKEX 日历冲突") }
                sessions += official.keys.filter { $0 <= end }; calendarEnd = end
            }
            var key: String?, seenKeys = Set<String>()
            repeat {
                let reply: HistoryReply = try request(.history, HistoryRequest(security: owner, beginTime: firstHistory, endTime: today, nextReqKey: key))
                guard reply.security == owner else { throw OpenDError.invalidResponse }
                for bar in reply.klList ?? [] where !bar.isBlank {
                    if let close = bar.closePrice, close.isFinite, close > 0 { closes[String(bar.time.prefix(10))] = close }
                }
                key = reply.nextReqKey?.isEmpty == false ? reply.nextReqKey : nil
                if let key, !seenKeys.insert(key).inserted { throw AnalysisError.message("历史日线分页未推进") }
            } while key != nil
        } catch is CancellationError { throw CancellationError() }
        catch { historyError = error.localizedDescription }
        for expiry in selected {
            try Task.checkCancellation()
            let dte = MarketDate.distance(from: today, to: expiry, market: stock.market)!
            let rv = expiry <= calendarEnd ? StrategyEngine.realizedVolatility(closes: closes, sessions: sessions, today: today, expiry: expiry) : nil
            var earningsBlocked: Bool?
            do {
                let begin = max(today, MarketDate.adding(-6, to: expiry, market: stock.market)!)
                let earnings: EarningsReply = try request(.earnings, EarningsRequest(market: stock.market.openDCode, beginDate: begin, endDate: expiry))
                let matching = (earnings.itemList ?? []).filter { $0.security == owner }
                guard matching.allSatisfy({ $0.earningsDate != nil }) else { throw AnalysisError.message("财报日期缺失") }
                earningsBlocked = matching.contains { ($0.earningsDate ?? "") >= begin && ($0.earningsDate ?? "") <= expiry }
            } catch is CancellationError { throw CancellationError() }
            catch { earningsBlocked = nil }
            let chain: ChainReply
            do { chain = try request(.chain, ChainRequest(owner: owner, beginTime: expiry, endTime: expiry)) }
            catch is CancellationError { throw CancellationError() }
            catch {
                for i in results.indices where policies[results[i].strategy] != nil { results[i].incomplete = true; results[i].reasons.append("\(expiry)：\(error.localizedDescription)") }; continue
            }
            let rawContracts = (chain.optionChain ?? []).flatMap { $0.option ?? [] }.flatMap { [$0.put, $0.call].compactMap { $0 } }
            if rawContracts.contains(where: { $0.optionExData == nil || ![1,2].contains($0.optionExData?.type ?? 0) }) {
                for i in results.indices where policies[results[i].strategy] != nil { results[i].incomplete = true; results[i].reasons.append("\(expiry)：期权链身份字段缺失") }
            }
            let contracts = rawContracts.filter { item in
                guard let option = item.optionExData, let strategy: Strategy = option.type == 1 ? .cc : option.type == 2 ? .csp : nil,
                      let policy = policies[strategy], (policy.minDTE...policy.maxDTE).contains(dte) else { return false }
                return option.strikePrice >= policy.minStrike && option.strikePrice <= policy.maxStrike
            }
            for offset in stride(from: 0, to: contracts.count, by: 100) {
                let batch = Array(contracts[offset..<min(offset + 100, contracts.count)])
                let quotes: [Snapshot]
                do {
                    let reply: SnapshotReply = try request(.snapshot, SnapshotRequest(securityList: batch.map { $0.basic.security }))
                    quotes = reply.snapshotList ?? []
                } catch is CancellationError { throw CancellationError() }
                catch {
                    for i in results.indices where policies[results[i].strategy] != nil { results[i].incomplete = true; results[i].reasons.append("快照失败：\(error.localizedDescription)") }; continue
                }
                let received = Date()
                for item in batch {
                    guard let option = item.optionExData else { continue }
                    let strategy: Strategy = option.type == 1 ? .cc : .csp
                    guard let index = results.firstIndex(where: { $0.strategy == strategy }), let policy = policies[strategy] else { continue }
                    let matches = quotes.filter { $0.basic.security == item.basic.security }
                    guard matches.count == 1, let quote = matches.first else { results[index].incomplete = true; results[index].reasons.append("\(item.basic.security.code)：快照缺失或重复"); continue }
                    if option.optionStandardType == 2 || option.suspend || quote.basic.isSuspend == true || (quote.basic.secStatus != nil && quote.basic.secStatus != 1 && quote.basic.secStatus != 0) {
                        results[index].reasons.append("\(item.basic.security.code)：非标准合约、停牌或不可用证券状态")
                        continue
                    }
                    var gaps: [String] = []
                    if option.owner != owner || option.strikeTime != expiry || quote.optionExData?.owner != owner || quote.optionExData?.strikePrice != option.strikePrice || quote.optionExData?.type != option.type { gaps.append("合约身份字段不一致") }
                    if option.optionStandardType != 1 || item.basic.secType != 8 || option.suspend || quote.basic.isSuspend != false || quote.basic.secStatus != 1 { gaps.append("合约非标准、停牌或状态未知") }
                    if Date().timeIntervalSince(observed) > 300 { gaps.append("扫描期间标的现价已过期，请减少关注或收窄期限") }
                    if let historyError { gaps.append("历史数据：\(historyError)") }
                    let rawShares = quote.optionExData?.contractSizeFloat ?? quote.optionExData?.contractSize.map(Double.init)
                    let validShares = rawShares.map { $0.isFinite && $0 > 0 && $0 < Double(Int.max) && $0.rounded() == $0 } ?? false
                    let shares = validShares ? rawShares.map(Int.init) : nil
                    if shares != item.basic.lotSize { gaps.append("期权链与快照合约股数冲突") }
                    if let other = quote.optionExData?.contractMultiplier, other != rawShares { gaps.append("快照合约规模字段冲突") }
                    let evidence = OptionEvidence(id: "\(stock.market.rawValue).\(item.basic.security.code)", stockID: stock.id,
                        strategy: strategy, expiry: expiry, dte: dte, spot: spot, strike: option.strikePrice, multiplier: shares,
                        bid: quote.basic.bidPrice, ask: quote.basic.askPrice, tick: quote.basic.priceSpread,
                        openInterest: quote.optionExData?.openInterest.flatMap { $0 >= 0 ? $0 : nil }, delta: quote.optionExData?.delta,
                        iv: quote.optionExData?.impliedVolatility.map { $0 / 100 }, rv: rv, cnyRate: fx,
                        earningsBlocked: earningsBlocked, receivedAt: received, spotObservedAt: observed, unavailable: gaps)
                    let evaluated = StrategyEngine.evaluate(evidence, policy: policy, market: stock.market, now: Date())
                    if let candidate = evaluated.candidate { results[index].candidates.append(candidate) }
                    results[index].incomplete = results[index].incomplete || evaluated.incomplete
                    results[index].reasons += evaluated.reasons.map { "\(item.basic.security.code)：\($0)" }
                }
            }
        }
        for i in results.indices {
            results[i].candidates = StrategyEngine.rank(results[i].candidates)
            results[i].reasons = Array(Set(results[i].reasons)).sorted()
            if results[i].candidates.isEmpty && results[i].reasons.isEmpty { results[i].reasons = ["行权价与期限范围内没有合格合约"] }
        }
        return results
    }
}

private struct KeepAliveRequest: Encodable { let time: String }
private struct EmptyReply: Decodable {}
