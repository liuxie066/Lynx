import SwiftUI
#if canImport(LynxCore)
import LynxCore
#endif

struct OptionsPage: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        HStack {
            MarketPicker()
            Spacer()
            Text(store.refreshing ? store.progress : store.record(store.market).message).font(.callout).foregroundStyle(.secondary)
            Button { store.refresh() } label: { Label("刷新", systemImage: "arrow.clockwise") }
                .disabled(store.refreshing || store.preview)
        }
        if let result = store.record(store.market).result {
            Text("数据时间：\(result.completedAt.formatted(date: .abbreviated, time: .standard)) · \(store.record(store.market).stale ? "历史参考 / 不完整" : "已更新")")
                .font(.caption).foregroundStyle(.secondary)
        }
        ForEach(Strategy.allCases) { strategy in OptionsCard(strategy: strategy) }
    }
}

// Presentation fixtures exist only behind --preview; they never enter configuration or live data.
private struct OptionDisplayRow: Identifiable {
    let id: String
    let symbol: String
    let child: Bool
    let price: String
    let expiry: String
    let strike: String
    let premium: String
    let yield: String
    let annual: String
    let distance: String
    let collateral: String
    let change: String
    var stockID: String = ""
    var explanation: String = ""
}

struct OptionsCard: View {
    @EnvironmentObject private var store: AppStore
    let strategy: Strategy
    @ViewState<Set<String>> private var expanded = []
    private var stocks: [WatchStock] { store.stocks.filter { $0[strategy].enabled } }
    private var rows: [OptionDisplayRow] {
        guard store.preview else {
            guard let result = store.record(store.market).result else { return [] }
            return result.representatives(strategy).enumerated().flatMap { rank, best in
                let candidates = result.stocks.first { $0.stock.id == best.evidence.stockID && $0.strategy == strategy }?.candidates ?? []
                return (expanded.contains(best.evidence.stockID) ? candidates : [best]).enumerated().map { offset, candidate in
                    let e = candidate.evidence
                    func money(_ value: Double) -> String { String(format: "%.2f", value) }
                    func percent(_ value: Double) -> String { String(format: "%.2f%%", value * 100) }
                    return OptionDisplayRow(id: candidate.id, symbol: String(e.stockID.dropFirst(3)) + (offset == 0 && rank < 3 ? " · #\(rank + 1)" : ""), child: offset > 0,
                        price: money(e.spot), expiry: e.expiry, strike: money(e.strike), premium: money(candidate.netPremium),
                        yield: percent(candidate.holdingYield), annual: percent(candidate.annualYield), distance: percent(candidate.distance),
                        collateral: strategy == .csp ? money(candidate.collateral) : "\(e.multiplier ?? 0) 股",
                        change: offset > 0 ? "—" : store.record(store.market).changes[candidate.id] ?? "—", stockID: e.stockID, explanation: candidate.explanation)
                }
            }
        }
        return stocks.enumerated().flatMap { index, stock in
            let main = fixture(stock: stock, index: index, child: false)
            return expanded.contains(stock.id) ? [main, fixture(stock: stock, index: index, child: true)] : [main]
        }
    }
    private func fixture(stock: WatchStock, index: Int, child: Bool) -> OptionDisplayRow {
        OptionDisplayRow(id: stock.id + (child ? "-child" : ""), symbol: stock.code, child: child,
                         price: ["189.50", "135.20", "338.40"][index % 3], expiry: child ? "12月25日" : "12月18日",
                         strike: strategy == .csp ? "180.00" : "200.00", premium: child ? "152.00" : "235.00",
                         yield: child ? "0.84%" : "1.31%", annual: child ? "12.1%" : "19.0%",
                         distance: "5.01%", collateral: strategy == .csp ? "18,000.00" : "100 股",
                         change: child ? "—" : ["持平", "新增", "上升 1 位"][index % 3], stockID: stock.id)
    }
    var body: some View {
        Card {
            HStack(spacing: 12) {
                Text(strategy.rawValue).font(.system(.headline, design: .rounded)).foregroundStyle(Theme.accent)
                Text(strategy.title).font(.headline)
                Spacer()
                Text("\(stocks.count) 个已启用标的").font(.callout).foregroundStyle(.secondary)
            }.padding(22)
            Table(rows) {
                TableColumn("标的 / 现价") { row in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.child ? "其他候选" : row.symbol).fontWeight(row.child ? .regular : .semibold)
                        Text(row.child ? row.symbol : row.price).font(.caption).foregroundStyle(.secondary)
                    }.padding(.leading, row.child ? 18 : 0).padding(.vertical, 6).help(row.explanation)
                }.width(min: 115, ideal: 145)
                TableColumn("到期日", value: \.expiry).width(min: 75, ideal: 90)
                TableColumn("行权价", value: \.strike).width(min: 65, ideal: 80)
                TableColumn("每手净权利金", value: \.premium).width(min: 95, ideal: 110)
                TableColumn("持有期收益率", value: \.yield).width(min: 95, ideal: 105)
                TableColumn("年化收益率", value: \.annual).width(min: 85, ideal: 100)
                TableColumn(strategy == .csp ? "接货折价" : "上行空间", value: \.distance).width(min: 75, ideal: 90)
                TableColumn(strategy == .csp ? "担保现金" : "担保股数", value: \.collateral).width(min: 90, ideal: 105)
                TableColumn("距上次推荐变化", value: \.change).width(min: 112, ideal: 125)
                TableColumn("") { row in
                    if !row.child {
                        Button {
                            if expanded.contains(row.stockID) { expanded.remove(row.stockID) } else { expanded.insert(row.stockID) }
                        } label: {
                            Image(systemName: expanded.contains(row.stockID) ? "chevron.down" : "chevron.right")
                                .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        }.buttonStyle(.plain).accessibilityLabel("\(expanded.contains(row.stockID) ? "收起" : "展开") \(row.symbol) 其他候选")
                    }
                }.width(28)
            }.tableStyle(.inset).alternatingRowBackgrounds(.disabled)
                .frame(height: rows.isEmpty ? 36 : CGFloat(rows.count * 54 + 36))
            if !store.preview, let result = store.record(store.market).result {
                ForEach(result.stocks.filter { $0.strategy == strategy && !$0.reasons.isEmpty }) { stock in
                    DisclosureGroup("\(stock.stock.code) · \(stock.incomplete ? "数据不完整" : stock.candidates.isEmpty ? "无合格候选" : "其他合约筛选原因")") {
                        VStack(alignment: .leading, spacing: 6) { ForEach(stock.reasons, id: \.self) { Text($0).textSelection(.enabled) } }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.horizontal, 22).padding(.vertical, 8)
                }
            }
            Text("一手期权分析；不验证真实资产。手续费为 Futu HK 费率估算，以实际账户收费为准。\(strategy == .cc ? "CC 假设覆盖表中股数，收益率不代表持仓总回报。" : "担保现金不表示账户资金足够。")")
                .font(.caption).foregroundStyle(.secondary).padding(18)
            if rows.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 25)).foregroundStyle(.tertiary)
                    Text(stocks.isEmpty ? "尚无已启用标的" : "暂时没有推荐结果").font(.headline)
                    Text(stocks.isEmpty ? "在配置页添加股票，并分别开启 CSP 或 CC。" : "点击刷新获取行情；待设置和数据不可用原因会显示在下方。")
                        .font(.callout).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 42)
            }
        }
    }
}
