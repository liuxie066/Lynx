import SwiftUI
#if canImport(LynxCore)
import LynxCore
#endif

struct OptionsPage: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        let record = store.record(store.market)
        HStack(spacing: 16) {
            MarketPicker()
            Spacer(minLength: 16)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    if store.refreshing { ProgressView().controlSize(.small) }
                    Text(store.refreshing ? store.progress : record.message)
                        .font(.callout).lineLimit(2)
                }
                if let result = record.result {
                    Label("\(result.completedAt.formatted(date: .abbreviated, time: .standard)) · \(record.stale ? "历史参考 / 不完整" : "已更新")",
                          systemImage: record.stale ? "clock.badge.exclamationmark" : "clock")
                        .font(.caption).foregroundStyle(record.stale ? Theme.warning : .secondary)
                }
            }.foregroundStyle(.secondary)
            Button { store.refresh() } label: {
                Label(store.refreshing ? "刷新中…" : "刷新", systemImage: "arrow.clockwise")
                    .frame(minWidth: 65)
            }.buttonStyle(.bordered).disabled(store.refreshing || store.preview).help("刷新两个市场的行情（⌘R）")
        }
        ForEach(Strategy.allCases) { strategy in OptionsCard(strategy: strategy) }
    }
}

struct OptionDisplayRow: Identifiable {
    let id: String
    let symbol: String
    let child: Bool
    let spot: Double
    let expiry: String
    let strikeValue: Double
    let premiumValue: Double
    let holdingYield: Double
    let annualYield: Double
    let distanceValue: Double
    let cash: Double?
    let shares: Int?
    let change: String
    var stockID: String = ""
    var explanation: String = ""
    var rank: Int? = nil
    var otherCount = 0
    // Format only cells requested by Table, rather than every off-screen contract.
    private func money(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }
    private func percent(_ value: Double) -> String { value.formatted(.percent.precision(.fractionLength(2))) }
    var price: String { money(spot) }
    var strike: String { money(strikeValue) }
    var premium: String { money(premiumValue) }
    var yield: String { percent(holdingYield) }
    var annual: String { percent(annualYield) }
    var distance: String { percent(distanceValue) }
    var collateral: String { cash.map(money) ?? shares.map { "\($0) 股" } ?? "不可用" }
}

// Keep presentation linear in the visible contracts; the native Table owns scrolling/reuse.
enum OptionPresentation {
    static func rows(result: MarketResult, strategy: Strategy, expanded: Set<String>, changes: [String: String]) -> [OptionDisplayRow] {
        let groups = Dictionary(result.stocks.filter { $0.strategy == strategy }.map { ($0.stock.id, $0.candidates) }, uniquingKeysWith: { first, _ in first })
        return result.representatives(strategy).enumerated().flatMap { rank, best in
            let candidates = groups[best.evidence.stockID] ?? [best]
            return (expanded.contains(best.evidence.stockID) ? candidates : [best]).enumerated().map { offset, candidate in
                let e = candidate.evidence
                return OptionDisplayRow(id: candidate.id, symbol: String(e.stockID.dropFirst(3)), child: offset > 0,
                    spot: e.spot, expiry: e.expiry, strikeValue: e.strike, premiumValue: candidate.netPremium,
                    holdingYield: candidate.holdingYield, annualYield: candidate.annualYield, distanceValue: candidate.distance,
                    cash: strategy == .csp ? candidate.collateral : nil, shares: e.multiplier,
                    change: offset > 0 ? "—" : changes[candidate.id] ?? "—", stockID: e.stockID, explanation: candidate.explanation,
                    rank: offset == 0 && rank < 3 ? rank + 1 : nil, otherCount: offset == 0 ? max(0, candidates.count - 1) : 0)
            }
        }
    }
    static func tableHeight(rowCount: Int) -> CGFloat { CGFloat(min(max(0, rowCount), 7) * 54 + 36) }
}

struct OptionsCard: View {
    @EnvironmentObject private var store: AppStore
    let strategy: Strategy
    @ViewState<Set<String>> private var expanded = []

    // Presentation fixtures are isolated behind --preview and never become live results.
    private func fixture(stock: WatchStock, index: Int, child: Bool) -> OptionDisplayRow {
        OptionDisplayRow(id: stock.id + (child ? "-child" : ""), symbol: stock.code, child: child,
                         spot: [189.50, 135.20, 338.40][index % 3], expiry: child ? "2026-12-25" : "2026-12-18",
                         strikeValue: strategy == .csp ? 180 : 200, premiumValue: child ? 152 : 235,
                         holdingYield: child ? 0.0084 : 0.0131, annualYield: child ? 0.121 : 0.19,
                         distanceValue: 0.0501, cash: strategy == .csp ? 18000 : nil, shares: 100,
                         change: child ? "—" : ["持平", "新增", "上升 1 位"][index % 3], stockID: stock.id,
                         rank: child ? nil : index + 1, otherCount: child ? 0 : 1)
    }
    var body: some View {
        let stocks = store.stocks.filter { $0[strategy].enabled }
        let record = store.record(store.market)
        let rows: [OptionDisplayRow] = store.preview ? stocks.enumerated().flatMap { index, stock in
            expanded.contains(stock.id) ? [fixture(stock: stock, index: index, child: false), fixture(stock: stock, index: index, child: true)] : [fixture(stock: stock, index: index, child: false)]
        } : record.result.map { OptionPresentation.rows(result: $0, strategy: strategy, expanded: expanded, changes: record.changes) } ?? []
        Card {
            StrategyHeader(strategy: strategy, detail: "\(stocks.count) 个已启用标的 · \(store.market.currency)")
            Divider()
            if !rows.isEmpty {
                optionsTable(rows)
                if rows.count > 7 {
                    Text("\(rows.count) 条合约 · 在表格内滚动查看")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, Theme.inset).padding(.vertical, 8)
                }
            } else {
                emptyState(stocks: stocks, record: record)
            }
            if !store.preview, let result = record.result {
                ForEach(result.stocks.filter { $0.strategy == strategy && !$0.reasons.isEmpty }) { stock in
                    Divider()
                    DisclosureGroup("\(stock.stock.code) · \(stock.incomplete ? "数据不完整" : stock.candidates.isEmpty ? "无合格候选" : "其他合约筛选原因")") {
                        LazyVStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(stock.reasons.enumerated()), id: \.offset) { _, reason in Text(reason).textSelection(.enabled) }
                        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
                    }.font(.callout).padding(.horizontal, Theme.inset).padding(.vertical, 12)
                }
            }
            Divider()
            Text("一手期权分析；不验证真实资产。手续费为 Futu HK 费率估算，以实际账户收费为准。\(strategy == .cc ? "CC 假设覆盖表中股数，收益率不代表持仓总回报。" : "担保现金不表示账户资金足够。")")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.inset).padding(.vertical, 14)
        }
    }
    private func optionsTable(_ rows: [OptionDisplayRow]) -> some View {
        Table(rows) {
            TableColumn("标的 / 现价") { row in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(row.child ? "其他候选" : row.symbol).fontWeight(row.child ? .regular : .semibold)
                        if let rank = row.rank {
                            Text("\(rank)").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.selectionInk)
                                .padding(.horizontal, 5).padding(.vertical, 2)
                                .background(Theme.selection, in: RoundedRectangle(cornerRadius: 4))
                                .accessibilityLabel("推荐第 \(rank) 位")
                        }
                    }
                    Text(row.child ? row.symbol : row.price).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }.padding(.leading, row.child ? 18 : 0).padding(.vertical, 6).help(row.explanation)
            }.width(min: 115, ideal: 140)
            TableColumn("到期日", value: \.expiry).width(min: 88, ideal: 94)
            TableColumn("行权价") { row in number(row.strike) }.width(min: 65, ideal: 75)
            TableColumn("每手净权利金") { row in number(row.premium) }.width(min: 94, ideal: 104)
            TableColumn("持有期收益率") { row in number(row.yield) }.width(min: 94, ideal: 104)
            TableColumn("年化收益率") { row in number(row.annual) }.width(min: 84, ideal: 94)
            TableColumn(strategy == .csp ? "接货折价" : "上行空间") { row in number(row.distance) }.width(min: 74, ideal: 84)
            TableColumn(strategy == .csp ? "担保现金" : "担保股数") { row in number(row.collateral) }.width(min: 89, ideal: 104)
            TableColumn("距上次推荐变化") { row in Text(row.change).font(.callout).foregroundStyle(.secondary) }.width(min: 112, ideal: 120)
            TableColumn("") { row in
                if !row.child && row.otherCount > 0 {
                    Button {
                        if expanded.contains(row.stockID) { expanded.remove(row.stockID) } else { expanded.insert(row.stockID) }
                    } label: {
                        Image(systemName: expanded.contains(row.stockID) ? "chevron.down" : "chevron.right")
                            .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            .frame(width: 24, height: 28).contentShape(Rectangle())
                    }.buttonStyle(.borderless)
                        .accessibilityLabel("\(expanded.contains(row.stockID) ? "收起" : "展开") \(row.symbol) 的 \(row.otherCount) 个其他候选")
                        .accessibilityValue(expanded.contains(row.stockID) ? "已展开" : "已收起")
                        .help("\(row.otherCount) 个其他合格候选")
                }
            }.width(28)
        }.tableStyle(.inset).alternatingRowBackgrounds(.enabled)
            .font(.system(size: 12)).frame(height: OptionPresentation.tableHeight(rowCount: rows.count))
            .accessibilityLabel("\(store.market.title) \(strategy.rawValue) 合约")
    }
    private func number(_ value: String) -> some View {
        Text(value).monospacedDigit().frame(maxWidth: .infinity, alignment: .trailing)
    }
    @ViewBuilder private func emptyState(stocks: [WatchStock], record: MarketRecord) -> some View {
        if stocks.isEmpty {
            EmptyState(symbol: "slider.horizontal.3", title: "尚无已启用标的", detail: "添加关注股票，并开启 \(strategy.rawValue) 后开始分析。")
            Button("前往配置") { store.page = .configuration }.buttonStyle(.bordered)
                .frame(maxWidth: .infinity).padding(.bottom, 24)
        } else if store.refreshing {
            EmptyState(symbol: "arrow.clockwise", title: "正在获取行情", detail: "完成后会在这里显示合格合约。你可以继续浏览其他页面。")
        } else if record.result != nil {
            EmptyState(symbol: "line.3.horizontal.decrease.circle", title: record.stale ? "暂无可用候选" : "本轮没有合格候选",
                       detail: "展开下方标的查看筛选或数据原因；也可以在配置页调整参数。")
        } else {
            EmptyState(symbol: "chart.xyaxis.line", title: "等待首次行情", detail: "登录本机 OpenD 后点击刷新，查看符合条件的合约。")
        }
    }
}
