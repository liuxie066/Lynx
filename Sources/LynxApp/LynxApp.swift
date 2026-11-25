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
        .windowStyle(.hiddenTitleBar)
        MenuBarExtra("Lynx", systemImage: "chart.xyaxis.line") { LynxMenu().environmentObject(store) }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("立即刷新") { store.refresh() }
                    .keyboardShortcut("r").disabled(store.refreshing || store.preview)
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    store.page = .settings; store.openMainWindow?()
                    NSApp.activate(ignoringOtherApps: true)
                }.keyboardShortcut(",")
            }
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
    static let sidebar = adaptive(light: 0xECEEF2, dark: 0x25262A)
    static let border = adaptive(light: 0xE2E5EB, dark: 0x40434B)
    static let accent = adaptive(light: 0x0067D9, dark: 0x6AA9FF)
    static let subtle = adaptive(light: 0xF7F9FC, dark: 0x30333A)
    static let warning = adaptive(light: 0x8A5700, dark: 0xE8BD6A)
    static let selectionInk = adaptive(light: 0x005BC0, dark: 0x8ABEFF)
    static let selection = adaptive(light: 0xE8F1FF, dark: 0x233B59)
    static let inactiveSelection = adaptive(light: 0xE3E6EB, dark: 0x3A3D44)
    static let inset: CGFloat = 24
    static let gap: CGFloat = 24
    static let ink = adaptive(light: 0x20242C, dark: 0xF2F3F5)
    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, alpha: 1)
        })
    }
}

struct Card<Content: View>: View {
    @Environment(\.colorSchemeContrast) private var contrast
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(contrast == .increased ? Color.primary.opacity(0.6) : Theme.border, lineWidth: 1))
    }
}

struct StrategyHeader: View {
    let strategy: Strategy
    let detail: String
    var body: some View {
        HStack(spacing: 10) {
            Text(strategy.rawValue).font(.system(size: 18, weight: .semibold))
            Text(strategy.title).font(.system(size: 13)).foregroundStyle(.secondary)
            Spacer(minLength: 16)
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
        }.padding(.horizontal, Theme.inset).frame(minHeight: 68)
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let detail: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 26, weight: .light))
                .foregroundStyle(Theme.accent).accessibilityHidden(true)
            Text(title).font(.system(size: 14, weight: .semibold))
            Text(detail).font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(.horizontal, 24).padding(.vertical, 28)
    }
}

struct RootView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.controlActiveState) private var controlActiveState
    @FocusState private var focusedPage: Page?
    @ViewState<Bool> private var sidebarVisible = true
    var body: some View {
        HStack(spacing: 0) {
            if sidebarVisible {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 5) {
                    Image(colorScheme == .dark ? "BrandMarkDark" : "BrandMarkLight")
                        .resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
                    Text("Lynx").font(.system(size: 15))
                }.padding(.leading, 88).frame(height: 32)
                    .frame(height: 62, alignment: .top)
                VStack(spacing: 4) {
                    ForEach(Page.allCases.prefix(3)) { item in
                        navigationButton(item)
                    }
                }.padding(.horizontal, 12).padding(.top, 12)
                Spacer()
                navigationButton(.settings).padding(.horizontal, 12)
                Divider().padding(.horizontal, 12).padding(.top, 20)
                VStack(alignment: .leading, spacing: 8) {
                    if store.preview { Label("界面预览 · 离线数据", systemImage: "eye").foregroundStyle(.secondary) }
                    Label(store.refreshing ? store.progress : store.connectionMessage, systemImage: "network").foregroundStyle(.secondary)
                }.font(.system(size: 12)).lineLimit(4).help(store.refreshing ? store.progress : store.connectionMessage).padding(24)
            }.frame(width: 220).background(Theme.sidebar)
                .onMoveCommand { direction in
                    let pages = Page.allCases
                    let index = pages.firstIndex(of: store.page ?? .options) ?? 0
                    if direction == .down { store.page = pages[min(index + 1, pages.count - 1)] }
                    if direction == .up { store.page = pages[max(index - 1, 0)] }
                    if direction == .up || direction == .down { focusedPage = store.page }
                }
            Divider()
            }
            VStack(spacing: 0) {
                HStack {
                    Text((store.page ?? .options).rawValue).font(.system(size: 22, weight: .semibold))
                    Spacer()
                    Button { sidebarVisible.toggle() } label: { Image(systemName: "sidebar.left") }
                        .help(sidebarVisible ? "隐藏边栏" : "显示边栏").accessibilityLabel(sidebarVisible ? "隐藏边栏" : "显示边栏")
                    Button { store.page = .settings } label: { Image(systemName: "slider.horizontal.3") }
                        .help("设置").accessibilityLabel("设置")
                }.buttonStyle(.borderless).foregroundStyle(Theme.ink)
                    .padding(.leading, sidebarVisible ? 32 : 88).padding(.trailing, 32).frame(height: 62)
                Divider()
                if let error = store.storageError ?? store.historyError {
                    Label(error, systemImage: "exclamationmark.triangle").font(.callout).foregroundStyle(.orange).padding(12)
                }
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.gap) {
                        switch store.page ?? .options {
                        case .options: OptionsPage()
                        case .configuration: ConfigurationPage()
                        case .ai: AIPage()
                        case .settings: SettingsPage()
                        }
                    }.padding(.horizontal, 32).padding(.vertical, 24).frame(maxWidth: 1600, alignment: .leading).frame(maxWidth: .infinity)
                }
            }
            .background(Theme.canvas)
        }
        .ignoresSafeArea(.container, edges: .top)
        .onAppear { store.openMainWindow = { openWindow(id: "main") } }
        .font(.system(size: 13)).foregroundStyle(Theme.ink)
        .buttonBorderShape(.roundedRectangle(radius: 6))
        .frame(minWidth: 1180, minHeight: 720)
    }
    private func navigationButton(_ page: Page) -> some View {
        Button { store.page = page } label: {
            HStack(spacing: 10) {
                Image(systemName: page.symbol).frame(width: 19)
                Text(page.rawValue)
                Spacer()
            }.font(.system(size: 15, weight: store.page == page ? .medium : .regular))
                .foregroundStyle(store.page == page && controlActiveState != .inactive ? Theme.selectionInk : Theme.ink)
                .padding(.horizontal, 12).frame(height: 40)
                .background(store.page == page ? (controlActiveState == .inactive ? Theme.inactiveSelection : Theme.selection) : .clear, in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).focused($focusedPage, equals: page)
            .accessibilityLabel(page.rawValue).accessibilityAddTraits(store.page == page ? .isSelected : [])
    }
}

struct MarketPicker: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        NativeMarketPicker(selection: $store.market).frame(width: 184, height: 32)
    }
}

private struct NativeMarketPicker: NSViewRepresentable {
    @Binding var selection: Market
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(labels: Market.allCases.map(\.title), trackingMode: .selectOne,
                                         target: context.coordinator, action: #selector(Coordinator.select(_:)))
        control.segmentStyle = .rounded
        control.controlSize = .large
        control.font = .systemFont(ofSize: 13)
        for index in Market.allCases.indices { control.setWidth(88, forSegment: index) }
        control.setAccessibilityLabel("市场")
        return control
    }
    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.parent = self
        control.selectedSegment = Market.allCases.firstIndex(of: selection) ?? 0
    }
    @MainActor final class Coordinator: NSObject {
        var parent: NativeMarketPicker
        init(_ parent: NativeMarketPicker) { self.parent = parent }
        @objc func select(_ sender: NSSegmentedControl) {
            guard Market.allCases.indices.contains(sender.selectedSegment) else { return }
            parent.selection = Market.allCases[sender.selectedSegment]
        }
    }
}

struct RoundedInput: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let label: String
    var enabled = true
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.controlSize = .large
        field.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        field.alignment = .right
        field.delegate = context.coordinator
        field.cell?.usesSingleLineMode = true
        return field
    }
    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        field.placeholderString = placeholder
        field.isEnabled = enabled
        field.setAccessibilityLabel(label)
        if field.stringValue != text { field.stringValue = text }
    }
    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: RoundedInput
        init(_ parent: RoundedInput) { self.parent = parent }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
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
