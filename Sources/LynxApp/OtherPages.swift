import SwiftUI
import AppKit
#if canImport(LynxCore)
import LynxCore
#endif

struct AIPage: View {
    @EnvironmentObject private var store: AppStore
    @ViewState<[AgentSkill: AgentSkill.Status]> private var statuses = [:]
    private let capabilities: [(String, String, String)] = [
        ("list.bullet.rectangle", "读取推荐", "与页面共用结果、前三和展开合约"),
        ("text.bubble", "解释结果", "排序、筛选原因、数据时间与有效参数"),
        ("star", "管理关注股票", "增删标的，名称在内部解析"),
        ("slider.horizontal.3", "修改策略参数", "独立开关 CSP / CC、修改或恢复参数"),
        ("gearshape", "配置 App", "连接、刷新、通知与登录启动"),
        ("arrow.clockwise", "查看状态与刷新", "共用 App 单轮任务，不重复取数")
    ]
    var body: some View {
        Card {
            Text("可用能力").font(.headline).padding(Theme.inset)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: Theme.gap) {
                ForEach(capabilities, id: \.0) { icon, name, detail in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: icon).foregroundStyle(Theme.accent).font(.system(size: 18)).frame(width: 20).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(name).font(.system(size: 14, weight: .semibold))
                            Text(detail).font(.system(size: 13)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(Theme.inset)
        }
        VStack(alignment: .leading, spacing: 14) {
        Text("智能体技能").font(.system(size: 15, weight: .semibold)).padding(.top, 8)
        HStack(alignment: .top, spacing: Theme.gap) {
            ForEach(Array(AgentSkill.allCases.reversed()), id: \.rawValue) { agent in
                let status = statuses[agent]
                Card {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(agent.rawValue).font(.system(size: 18, weight: .semibold))
                        Text("安装 Lynx 技能后，在 \(agent.rawValue) 中用自然语言操作本地 App。")
                            .font(.system(size: 13)).foregroundStyle(.secondary)
                        Text(status?.client ?? "正在检查客户端…").font(.caption).foregroundStyle(.secondary)
                        Divider().padding(.top, 16)
                        HStack {
                            Label(status?.installation ?? "正在检查技能…", systemImage: status?.installed == true ? "checkmark.circle" : "circle")
                                .font(.system(size: 12)).foregroundStyle(.secondary)
                            Spacer()
                            Button(status?.installed == true ? "更新技能" : "安装 Lynx 技能") {
                                do {
                                    guard let executable = Bundle.main.executableURL else { return }
                                    try agent.install(executable: executable); store.integrationMessage = "技能已写入；重开 Agent 会话后可发现。请保持 App 运行。"
                                } catch { store.integrationMessage = error.localizedDescription }; reloadStatuses()
                            }.buttonStyle(.bordered).controlSize(.large).disabled(store.preview || status == nil)
                            if status?.installed == true { Button("卸载", role: .destructive) {
                                do { try agent.uninstall(); store.integrationMessage = "已卸载 Lynx 技能" }
                                catch { store.integrationMessage = error.localizedDescription }; reloadStatuses()
                            }.buttonStyle(.bordered).controlSize(.large).disabled(store.preview || status == nil) }
                        }
                    }.padding(Theme.inset).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        }
        .onAppear { reloadStatuses() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in reloadStatuses() }
        VStack(alignment: .leading, spacing: 14) {
        Text("开始使用").font(.system(size: 15, weight: .semibold)).padding(.top, 8)
        Card {
            VStack(alignment: .leading, spacing: 16) {
                Text("安装后可在 Agent 中这样提问：").foregroundStyle(.secondary)
                Divider()
                Label("看看美股 CSP 的前三推荐，解释它们为什么排在前面。", systemImage: "arrow.up.right")
                Divider()
                Label("把刷新间隔改成 30 分钟。", systemImage: "arrow.up.right")
                Divider()
                Text("Agent 通过本机入口操作正在运行的 App。不读取真实账户、持仓或交易，不修改费用。系统通知权限仍由你在 macOS 中批准。").font(.callout).foregroundStyle(.secondary)
                if let message = store.integrationMessage { Text(message).font(.callout).textSelection(.enabled) }
            }.padding(Theme.inset).frame(maxWidth: .infinity, alignment: .leading)
        }
        }
    }
    private func reloadStatuses() {
        statuses = Dictionary(uniqueKeysWithValues: AgentSkill.allCases.map { ($0, $0.status()) })
    }
}

struct SettingsPage: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
        sectionTitle("OpenD 连接")
        Card {
            settingRow("本机 OpenD", detail: "请自行安装并登录官方 OpenD。") {
                Text(store.connectionMessage).font(.system(size: 12)).foregroundStyle(.secondary).textSelection(.enabled)
                Button(store.checking ? "检查中…" : "检查连接") { store.checkConnection() }
                    .disabled(store.checking || store.refreshing || !store.validPort || store.preview)
                    .controlSize(.large)
                if store.checking { ProgressView().controlSize(.small); Button("取消") { store.cancelCheck() } }
            }
            Divider()
            settingRow("连接端口", detail: "连接本机 127.0.0.1；与 OpenD 的监听端口保持一致。") {
                if !store.validPort { Text("端口必须为 1–65535。").font(.callout).foregroundStyle(.orange) }
                RoundedInput(placeholder: "端口", text: $store.portText, label: "OpenD 端口", enabled: !store.checking && !store.refreshing)
                    .frame(width: 85, height: 30).onChange(of: store.portText) { _, _ in store.savePort() }
            }
            Divider()
            settingRow("行情状态", detail: "刷新时分别检查两市场权限；不读取交易账户。") {
                HStack(alignment: .top, spacing: 24) {
                    ForEach(Market.allCases) { market in
                        VStack(alignment: .trailing, spacing: 6) {
                            Text("\(market.title)：\(store.record(market).message)").foregroundStyle(.secondary)
                            if let date = store.record(market).lastSuccess {
                                Text("上次成功：\(date.formatted(date: .abbreviated, time: .standard))").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.font(.callout)
            }
        }
        }
        VStack(alignment: .leading, spacing: 12) {
        sectionTitle("自动刷新")
        Card { settingRow("刷新间隔", detail: "两个市场共用间隔，分别判断开休市。") {
            Picker("刷新间隔", selection: store.preference(\.refreshMinutes)) {
                Text("关闭").tag(0); Text("10 分钟").tag(10); Text("30 分钟").tag(30); Text("1 小时").tag(60)
            }.frame(width: 130).labelsHidden().controlSize(.large)
        }
            footer("休市自动跳过；睡眠期间不刷新，唤醒后到期仅补一次。")
        }
        }
        VStack(alignment: .leading, spacing: 12) {
        sectionTitle("通知")
        Card {
            settingRow("推荐前三变化", detail: "合约、顺序或数量变化时通知；首次成功不通知。") { Toggle("推荐变化通知", isOn: store.preference(\.recommendationNotifications)).labelsHidden().toggleStyle(.switch) }
            Divider()
            settingRow("连接异常", detail: "同一故障只提醒一次，恢复后重新计数。") { Toggle("连接异常通知", isOn: store.preference(\.connectionNotifications)).labelsHidden().toggleStyle(.switch) }
            footer("\(store.notificationStatus)。开启时再申请系统通知权限。")
        }
        }
        VStack(alignment: .leading, spacing: 12) {
        sectionTitle("启动与窗口")
        Card {
            settingRow("登录时启动 Lynx", detail: "默认关闭，使用 macOS 登录项。") { Toggle("登录时启动", isOn: Binding(get: { store.launchAtLogin }, set: store.setLogin)).labelsHidden().toggleStyle(.switch) }
            Divider()
            settingRow("关闭窗口后留在菜单栏", detail: "继续按设置刷新；退出 Lynx 不停止 OpenD。") { Image(systemName: "checkmark").foregroundStyle(.secondary) }
        }
        }
        VStack(alignment: .leading, spacing: 12) {
        sectionTitle("数据与费用")
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("配置与最近结果只保存在本机，不做云同步。行情来自用户的 OpenD；CNY 费用门槛使用腾讯公开汇率。")
                Text("当前费用模型依据 Futu HK 的港美期权费率估算；其他 moomoo 地区尚未核验。费用随 App 更新，不提供手工修改。")
                if let message = store.integrationMessage { Text(message).foregroundStyle(.orange) }
            }.font(.callout).padding(Theme.inset)
        }
        }
    }
    private func sectionTitle(_ title: String) -> some View {
        Text(title).font(.system(size: 15, weight: .semibold)).padding(.horizontal, Theme.inset).padding(.top, 8)
    }
    private func footer(_ text: String) -> some View {
        VStack(spacing: 0) {
            Divider()
            Text(text).font(.system(size: 12)).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, Theme.inset).padding(.vertical, 14)
                .background(Theme.subtle)
        }
    }
    private func settingRow<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 14, weight: .medium)); Text(detail).font(.system(size: 12)).foregroundStyle(.secondary) }
            Spacer(minLength: 24); control()
        }.padding(.horizontal, Theme.inset).padding(.vertical, 20)
    }
}
