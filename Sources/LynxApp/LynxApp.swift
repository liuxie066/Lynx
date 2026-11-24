import SwiftUI
import AppKit
#if canImport(LynxCore)
import LynxCore
#endif

// Use the established property wrapper even when SDK 27 also exports a State macro.
// This keeps the skeleton buildable with Command Line Tools lacking SwiftUIMacros.
typealias ViewState<Value> = SwiftUI.State<Value>

struct LynxApp: App {
    @NSApplicationDelegateAdaptor(LynxDelegate.self) private var delegate
    @StateObject private var store = AppStore()
    var body: some Scene {
        Window("Lynx", id: "main") {
            RootView().environmentObject(store)
                .task { store.start() }
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in store.stop() }
        }
        .defaultSize(width: 1440, height: 920)
        MenuBarExtra("Lynx", systemImage: "chart.xyaxis.line") { LynxMenu().environmentObject(store) }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

enum Page: String, CaseIterable, Identifiable {
    case options = "期权", configuration = "配置", ai = "AI 集成", settings = "设置"
    var id: Self { self }
    var symbol: String {
        switch self {
        case .options: return "chart.xyaxis.line"
        case .configuration: return "slider.horizontal.3"
        case .ai: return "sparkles"
        case .settings: return "gearshape"
        }
    }
}

enum Theme {
    static let canvas = adaptive(light: 0xF5F6F8, dark: 0x1C1D20)
    static let panel = adaptive(light: 0xFFFFFF, dark: 0x2C2D32)
    static let border = adaptive(light: 0xE2E5EB, dark: 0x40434B)
    static let accent = adaptive(light: 0x0067D9, dark: 0x6AA9FF)
    static let ink = adaptive(light: 0x20242C, dark: 0xF2F3F5)
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border.opacity(0.75), lineWidth: 1))
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 7) {
                    Image(colorScheme == .dark ? "BrandMarkDark" : "BrandMarkLight")
                        .resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
                    Text("Lynx").font(.system(size: 15, weight: .semibold))
                }.padding(.horizontal, 20).padding(.top, 12)
                List(selection: $store.page) {
                    ForEach(Page.allCases.prefix(3)) { item in
                        Label(item.rawValue, systemImage: item.symbol).font(.system(size: 15)).tag(item)
                    }
                }.listStyle(.sidebar)
                Button { store.page = .settings } label: {
                    Label(Page.settings.rawValue, systemImage: Page.settings.symbol)
                        .font(.system(size: 15)).frame(maxWidth: .infinity, alignment: .leading).padding(9)
                        .background(store.page == .settings ? Theme.accent.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 8))
                }.buttonStyle(.plain).padding(.horizontal, 10)
                VStack(alignment: .leading, spacing: 8) {
                    if store.preview { Label("界面预览 · 离线数据", systemImage: "eye").foregroundStyle(.secondary) }
                    Label(store.refreshing ? store.progress : store.connectionMessage, systemImage: "network").foregroundStyle(.secondary)
                }.font(.caption).padding(18)
            }.navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 230)
        } detail: {
            VStack(spacing: 0) {
                if let error = store.storageError ?? store.historyError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).padding(12)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch store.page ?? .options {
                        case .options: OptionsPage()
                        case .configuration: ConfigurationPage()
                        case .ai: AIPage()
                        case .settings: SettingsPage()
                        }
                    }.padding(24)
                }
            }
            .background(Theme.canvas)
            .toolbar { ToolbarItem(placement: .principal) { Text((store.page ?? .options).rawValue).font(.system(size: 22, weight: .semibold)) } }
        }
        .onAppear { store.openMainWindow = { openWindow(id: "main") } }
        .tint(Theme.accent).foregroundStyle(Theme.ink)
        .frame(minWidth: 1180, minHeight: 720)
    }
}

struct MarketPicker: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        Picker("市场", selection: $store.market) { ForEach(Market.allCases) { Text($0.title).tag($0) } }
            .pickerStyle(.segmented).frame(width: 220).labelsHidden()
    }
}


@MainActor final class LynxDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.windows.first(where: { $0.title == "Lynx" })?.makeKeyAndOrderFront(nil)
        return true
    }
}

struct LynxMenu: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Button("打开 Lynx") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button(store.refreshing ? store.progress : "立即刷新") { store.refresh() }.disabled(store.refreshing)
        Picker("自动刷新", selection: store.preference(\.refreshMinutes)) {
            Text("关闭").tag(0); Text("10 分钟").tag(10); Text("30 分钟").tag(30); Text("1 小时").tag(60)
        }
        ForEach(Market.allCases) { market in
            Text("\(market.title)：\(store.record(market).message)")
            if let date = store.record(market).lastSuccess { Text("上次成功 \(date.formatted(date: .abbreviated, time: .shortened))") }
        }
        Text(store.connectionMessage)
        Divider()
        Button("退出 Lynx") { store.stop(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

@main enum LynxEntry {
    @MainActor static func main() {
        if CommandLine.arguments.dropFirst().first == "--agent" {
            do {
                guard CommandLine.arguments.count == 3 else { throw AnalysisError.message("用法：Lynx --agent '<JSON request>'") }
                let input = Data(CommandLine.arguments[2].utf8)
                _ = try JSONDecoder().decode(AgentRequest.self, from: input)
                let output = try AgentTransport.call(input)
                FileHandle.standardOutput.write(output); FileHandle.standardOutput.write(Data("\n".utf8))
                let envelope = try JSONSerialization.jsonObject(with: output) as? [String: Any]
                if envelope?["ok"] as? Bool != true { exit(1) }
            } catch { FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8)); exit(1) }
        } else { LynxApp.main() }
    }
}
