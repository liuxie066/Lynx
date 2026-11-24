import SwiftUI
#if canImport(LynxCore)
import LynxCore
#endif

struct AIPage: View {
    @EnvironmentObject private var store: AppStore
    @ViewState<Int> private var revision = 0
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
            Text("可用能力").font(.headline).padding(22)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 26) {
                ForEach(capabilities, id: \.0) { icon, name, detail in
                    VStack(alignment: .leading, spacing: 10) {
                        Image(systemName: icon).foregroundStyle(Theme.accent).font(.title3)
                        Text(name).font(.headline)
                        Text(detail).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(22)
        }
        HStack(alignment: .top, spacing: 24) {
            ForEach(AgentSkill.allCases, id: \.rawValue) { agent in
                Card {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(agent.rawValue).font(.title3.weight(.semibold))
                        Text(agent.installationStatus).font(.callout).foregroundStyle(.secondary)
                        Text(agent.clientStatus).font(.caption).foregroundStyle(.secondary)
                        HStack {
                            Button(agent.installed ? "更新技能" : "安装 Lynx 技能") {
                                do {
                                    guard let executable = Bundle.main.executableURL else { return }
                                    try agent.install(executable: executable); store.integrationMessage = "技能已写入；重开 Agent 会话后可发现。请保持 App 运行。"
                                } catch { store.integrationMessage = error.localizedDescription }; revision += 1
                            }.disabled(store.preview)
                            if agent.installed { Button("卸载", role: .destructive) {
                                do { try agent.uninstall(); store.integrationMessage = "已卸载 Lynx 技能" }
                                catch { store.integrationMessage = error.localizedDescription }; revision += 1
                            }.disabled(store.preview) }
                        }
                    }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
                }.id(agent.rawValue + String(revision))
            }
        }
        Card {
            VStack(alignment: .leading, spacing: 14) {
                Text("使用方式").font(.headline)
                Text("“看看美股 CSP 的前三推荐，解释它们为什么排在前面。”")
                Text("“把刷新间隔改成 30 分钟。”")
                Text("Agent 通过本机入口操作正在运行的 App。不读取真实账户、持仓或交易，不修改费用。系统通知权限仍由你在 macOS 中批准。").font(.callout).foregroundStyle(.secondary)
                if let message = store.integrationMessage { Text(message).font(.callout).textSelection(.enabled) }
            }.padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct SettingsPage: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Text("OpenD 连接").font(.headline)
        Card {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("本机 OpenD").font(.headline)
                    Text("请自行安装并登录官方 OpenD；刷新时检查市场行情权限。").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Text("127.0.0.1").foregroundStyle(.secondary)
                TextField("端口", text: $store.portText).frame(width: 85).textFieldStyle(.roundedBorder)
                    .disabled(store.checking || store.refreshing).onChange(of: store.portText) { _, _ in store.savePort() }
                Button(store.checking ? "检查中…" : "检查连接") { store.checkConnection() }
                    .disabled(store.checking || store.refreshing || !store.validPort || store.preview)
                if store.checking { Button("取消") { store.cancelCheck() } }
            }.padding(22)
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text(store.connectionMessage).textSelection(.enabled)
                if !store.validPort { Text("端口必须为 1–65535。").foregroundStyle(.orange) }
                ForEach(Market.allCases) { market in
                    Text("\(market.title)：\(store.record(market).message)")
                    if let date = store.record(market).lastSuccess { Text("上次成功：\(date.formatted(date: .abbreviated, time: .standard))").foregroundStyle(.secondary) }
                }
            }.font(.callout).padding(22).frame(maxWidth: .infinity, alignment: .leading)
        }
        Text("自动刷新").font(.headline)
        Card { settingRow("刷新间隔", detail: "共用间隔，分别判市；休市保留历史结果。") {
            Picker("刷新间隔", selection: store.preference(\.refreshMinutes)) {
                Text("关闭").tag(0); Text("10 分钟").tag(10); Text("30 分钟").tag(30); Text("1 小时").tag(60)
            }.frame(width: 130).labelsHidden()
        } }
        Text("通知").font(.headline)
        Card {
            settingRow("推荐前三变化", detail: "合约、顺序或数量变化时通知；首次成功不通知。") { Toggle("推荐变化通知", isOn: store.preference(\.recommendationNotifications)).labelsHidden().toggleStyle(.switch) }
            Divider()
            settingRow("连接异常", detail: "同一故障只提醒一次，恢复后重新计数。") { Toggle("连接异常通知", isOn: store.preference(\.connectionNotifications)).labelsHidden().toggleStyle(.switch) }
            Text(store.notificationStatus).font(.caption).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 18)
        }
        Text("启动与窗口").font(.headline)
        Card {
            settingRow("登录时启动 Lynx", detail: "默认关闭，使用 macOS 登录项。") { Toggle("登录时启动", isOn: Binding(get: { store.launchAtLogin }, set: store.setLogin)).labelsHidden().toggleStyle(.switch) }
            Divider()
            settingRow("关闭窗口后留在菜单栏", detail: "继续按设置刷新；退出 Lynx 不停止 OpenD。") { Image(systemName: "checkmark").foregroundStyle(.secondary) }
        }
        Text("数据与费用").font(.headline)
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text("配置与最近结果只保存在本机，不做云同步。行情来自用户的 OpenD；CNY 费用门槛使用腾讯公开汇率。")
                Text("当前费用模型依据 Futu HK 的港美期权费率估算；其他 moomoo 地区尚未核验。费用随 App 更新，不提供手工修改。")
                if let message = store.integrationMessage { Text(message).foregroundStyle(.orange) }
            }.font(.callout).padding(22)
        }
    }
    private func settingRow<Control: View>(_ title: String, detail: String, @ViewBuilder control: () -> Control) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.headline); Text(detail).font(.callout).foregroundStyle(.secondary) }
            Spacer(minLength: 24); control()
        }.padding(22)
    }
}
