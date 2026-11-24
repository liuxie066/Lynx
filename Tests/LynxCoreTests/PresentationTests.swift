import Foundation
import Testing
@testable import LynxCore
@testable import LynxApp

private func presentationResult(stocks: Int, contracts: Int, strategy: Strategy = .cc) throws -> MarketResult {
    let groups = try (0..<stocks).map { index in
        let stock = try WatchStock(market: .us, code: "STOCK\(index)")
        var group = StockResult(stock: stock, strategy: strategy)
        group.candidates = try (0..<contracts).map { offset in
            var e = evidence(strategy: strategy, id: "\(stock.id).\(offset)", shares: 50)
            e.stockID = stock.id
            return Candidate(evidence: e, policy: try policy(strategy: strategy), sellLimit: 2, fee: 3, netPremium: 97,
                             holdingYield: 0.02 - Double(offset) * 0.0001, annualYield: 0.3,
                             distance: Double(stocks - index) * 0.01, collateral: 5000, spread: 0.1)
        }
        return group
    }
    return MarketResult(market: .us, startedAt: Date(), completedAt: Date(), stocks: groups)
}

@Test func tablePresentationPreservesRankingAndExpandedHierarchy() throws {
    let result = try presentationResult(stocks: 4, contracts: 3)
    let best = result.representatives(.cc)
    let changes = [best[0].id: "上升 2 位"]
    let collapsed = OptionPresentation.rows(result: result, strategy: .cc, expanded: [], changes: changes)
    #expect(collapsed.map(\.id) == best.map(\.id))
    #expect(collapsed.map(\.rank) == [1, 2, 3, nil])
    #expect(collapsed.allSatisfy { !$0.child && $0.otherCount == 2 && $0.collateral == "50 股" })
    #expect(collapsed[0].change == "上升 2 位")
    let expanded = OptionPresentation.rows(result: result, strategy: .cc, expanded: [best[0].evidence.stockID], changes: changes)
    #expect(expanded.count == 6)
    #expect(expanded.prefix(3).map(\.id) == result.stocks[0].candidates.map(\.id))
    #expect(expanded.prefix(3).map(\.child) == [false, true, true])
    #expect(expanded[1].rank == nil && expanded[1].change == "—" && expanded[1].otherCount == 0)
    #expect(OptionPresentation.rows(result: result, strategy: .csp, expanded: [], changes: [:]).isEmpty)
}

@Test func largeExpandedTableKeepsEveryContractWithBoundedViewport() throws {
    let result = try presentationResult(stocks: 100, contracts: 60)
    let start = ContinuousClock.now
    let rows = OptionPresentation.rows(result: result, strategy: .cc, expanded: Set(result.stocks.map { $0.stock.id }), changes: [:])
    let elapsed = ContinuousClock.now - start
    #expect(rows.count == 6000)
    #expect(Set(rows.map(\.id)).count == 6000)
    #expect(rows.filter { !$0.child }.count == 100)
    #expect(rows.filter { $0.rank != nil }.count == 3)
    #expect(OptionPresentation.tableHeight(rowCount: rows.count) == OptionPresentation.tableHeight(rowCount: 7))
    #expect(OptionPresentation.tableHeight(rowCount: 1) < OptionPresentation.tableHeight(rowCount: 7))
    print("Presentation benchmark: 6,000 contracts, 100 stocks, \(elapsed); viewport \(OptionPresentation.tableHeight(rowCount: rows.count)) pt")
}

@Test func singleCandidateHasNoDisclosureAndEmptyResultHasNoRows() throws {
    let result = try presentationResult(stocks: 1, contracts: 1)
    let rows = OptionPresentation.rows(result: result, strategy: .cc, expanded: [result.stocks[0].stock.id], changes: [:])
    #expect(rows.count == 1 && rows[0].otherCount == 0 && !rows[0].child)
    let empty = try presentationResult(stocks: 0, contracts: 0)
    #expect(OptionPresentation.rows(result: empty, strategy: .cc, expanded: [], changes: [:]).isEmpty)
}

@Test @MainActor func cancelledNameResolutionCannotAddStockAfterDismissal() async throws {
    let store = AppStore(preview: true)
    let before = store.configuration.stocks
    let (started, signalStarted) = AsyncStream<Void>.makeStream()
    let (release, signalRelease) = AsyncStream<Void>.makeStream()
    defer { signalStarted.finish(); signalRelease.finish() }
    store.resolve = { _, market, _ in
        signalStarted.yield(())
        // Return a stock even after cancellation; the write boundary must still reject it.
        for await _ in release { break }
        return try WatchStock(market: market, code: "CANCELLED")
    }
    let task = Task { try await store.resolveAndAdd("CANCELLED", market: .us) }
    for await _ in started { break }
    task.cancel()
    signalRelease.yield(())
    do {
        _ = try await task.value
        Issue.record("Cancelled request unexpectedly succeeded")
    } catch is CancellationError { }
    #expect(store.configuration.stocks == before)
}
