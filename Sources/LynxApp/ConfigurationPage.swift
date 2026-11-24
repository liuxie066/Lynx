import SwiftUI
#if canImport(LynxCore)
import LynxCore
#endif

struct ConfigurationPage: View {
    @EnvironmentObject private var store: AppStore
    @ViewState<Bool> private var adding = false
    @ViewState<Bool> private var resolving = false
    @ViewState<Task<Void, Never>?> private var addTask = nil
    @ViewState<String> private var symbol = ""
    @ViewState<String?> private var addError = nil
    var body: some View {
        HStack(spacing: 16) {
            MarketPicker()
            Spacer()
            Text(store.preview ? "预览修改不保存" : "更改自动保存在本机").font(.callout).foregroundStyle(.secondary)
            Button { addError = nil; symbol = ""; adding = true } label: { Label("添加股票", systemImage: "plus") }.buttonStyle(.borderedProminent)
        }
        ForEach(Strategy.allCases) { strategy in
            Card {
                StrategyHeader(strategy: strategy, detail: "\(store.market.currency) · 两个方向独立配置")
                Divider()
                ConfigurationHeader()
                if store.stocks.isEmpty {
                    EmptyState(symbol: "plus.circle", title: "还没有关注股票", detail: "添加股票后，分别设置 CSP 和 CC 的行权价与期限。")
                }
                ForEach(store.stocks) { stock in
                    ConfigurationRow(code: stock.code, name: stock.name, market: stock.market, strategy: strategy, settings: store.settings(stockID: stock.id, strategy: strategy))
                        .contextMenu { Button("移除关注股票", role: .destructive) { store.removeStock(stock.id) } }
                    Divider().padding(.horizontal, 20)
                }
                Text(strategy == .csp ? "最高行权价作为接货上限。空白 DTE 默认美股 7–60 天、港股 7–90 天；默认 Delta 上限 0.40。" : "不填写持仓成本。收益率基数采用当前股价 × 一手期权对应的真实股数。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).padding(Theme.inset)
            }
        }
        .sheet(isPresented: $adding) {
            VStack(alignment: .leading, spacing: 18) {
                Text("添加\(store.market.title)股票").font(.title2.weight(.semibold))
                TextField(store.market == .us ? "股票代码，例如 AAPL" : "股票代码，例如 00700", text: $symbol).textFieldStyle(.roundedBorder).accessibilityLabel("股票名称或代码").disabled(resolving)
                Text("可输入股票名称或代码；通过 OpenD 验证，名称不唯一时会提示选择。").font(.callout).foregroundStyle(.secondary)
                if let addError { Text(addError).foregroundStyle(.red).font(.callout) }
                HStack {
                    Spacer()
                    Button("取消", role: .cancel) {
                        if resolving { addTask?.cancel() } else { adding = false }
                    }.keyboardShortcut(.cancelAction)
                    Button(resolving ? "识别中…" : "添加") {
                        resolving = true
                        let query = symbol, market = store.market
                        addTask = Task {
                            defer { resolving = false; addTask = nil }
                            do {
                                if store.preview { try store.addStock(code: query) }
                                else { _ = try await store.resolveAndAdd(query, market: market) }
                                symbol = ""; addError = nil; adding = false
                            } catch {
                                if Task.isCancelled { adding = false }
                                else { addError = error.localizedDescription }
                            }
                        }
                    }.keyboardShortcut(.defaultAction).disabled(resolving || symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(28).frame(width: 420)
                .interactiveDismissDisabled(resolving)
                .onDisappear { addTask?.cancel() }
        }
    }
}

private struct ConfigurationHeader: View {
    var body: some View {
        HStack(spacing: 16) {
            Text("标的").frame(width: 100, alignment: .leading)
            Text("启用").frame(width: 48)
            ForEach(["最低行权价", "最高行权价", "最短 DTE", "最长 DTE"], id: \.self) { Text($0).frame(maxWidth: .infinity, alignment: .leading) }
            Text("").frame(width: 90)
        }.font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            .padding(.horizontal, Theme.inset).padding(.vertical, 10).background(Theme.subtle)
        Divider()
    }
}

private struct ConfigurationRow: View {
    let code: String
    let name: String?
    let market: Market
    let strategy: Strategy
    @Binding var settings: StrategySettings
    @ViewState<Bool> private var expanded = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(code).fontWeight(.semibold)
                    if let name, !name.isEmpty { Text(name).font(.caption).foregroundStyle(.secondary).lineLimit(1).help(name) }
                }.frame(width: 100, alignment: .leading)
                Toggle("启用 \(code) \(strategy.rawValue)", isOn: $settings.enabled).labelsHidden().toggleStyle(.switch).controlSize(.small).frame(width: 48)
                parameter("最低行权价", text: $settings.minStrike)
                parameter("最高行权价", text: $settings.maxStrike)
                parameter("最短 DTE", text: $settings.minDTE)
                parameter("最长 DTE", text: $settings.maxDTE)
                Button { expanded.toggle() } label: {
                    HStack(spacing: 5) { Text("高级参数"); Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .semibold)) }
                }.buttonStyle(.borderless).foregroundStyle(.secondary).frame(width: 90).accessibilityLabel("\(code) \(strategy.rawValue) 高级参数")
            }
            if expanded {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("最大绝对 Delta")
                        TextField("0.40", text: $settings.maxAbsoluteDelta).textFieldStyle(.roundedBorder).monospacedDigit().frame(width: 90).accessibilityLabel("\(code) \(strategy.rawValue) 最大绝对 Delta")
                        Text("空白使用默认值；右键标的可移除关注").foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复默认") {
                            let enabled = settings.enabled, ceiling = settings.maxStrike
                            settings = StrategySettings(); settings.enabled = enabled
                            if strategy == .csp { settings.maxStrike = ceiling }
                        }
                    }
                    HStack(spacing: 18) {
                        advanced("最低年化", key: \.minAnnualYield)
                        advanced("最低净权利金 CNY", key: \.minNetPremiumCNY)
                        advanced("最大价差比例", key: \.maxSpread)
                        advanced("最低 IV/RV", key: \.minIVRV)
                        advanced("最低 IV−RV", key: \.minIVMinusRV)
                    }
                    Text("比例按小数填写，例如 0.10 = 10%。恢复默认保留方向开关和 CSP 接货上限；费用不可修改。").foregroundStyle(.secondary)
                }.font(.callout).padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.subtle, in: RoundedRectangle(cornerRadius: 8))
            }
            if let message = settings.validationMessage(for: strategy) {
                Label(message, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(Theme.warning)
            }
        }.padding(.horizontal, Theme.inset).padding(.vertical, 14)
    }
    private func advanced(_ label: String, key: WritableKeyPath<AdvancedSettings, Double>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption)
            TextField(label, value: Binding(get: { (settings.advanced ?? AdvancedSettings())[keyPath: key] }, set: { value in
                var advanced = settings.advanced ?? AdvancedSettings(); advanced[keyPath: key] = value; settings.advanced = advanced
            }), format: .number).textFieldStyle(.roundedBorder).monospacedDigit().frame(maxWidth: .infinity).accessibilityLabel("\(code) \(strategy.rawValue) \(label)")
        }
    }
    private func parameter(_ label: String, text: Binding<String>) -> some View {
        TextField(label == "最短 DTE" ? "7" : label == "最长 DTE" ? (market == .us ? "60" : "90") : "自动 / 未设置", text: text).textFieldStyle(.roundedBorder).monospacedDigit().frame(maxWidth: .infinity)
            .accessibilityLabel("\(code) \(strategy.rawValue) \(label)")
    }
}
