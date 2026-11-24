# Lynx · 冰川蓝主题色规范

版本：1.0 · 日期：2026-11-24

状态：冰川蓝主题方向已确认；本文件补齐实现用色与交互规则。当前仅为设计文档，尚未创建 SwiftUI 工程或 Color Assets，也未将此主题应用到现有 HTML 预览。

适用页面：期权、配置、AI 集成、设置。产品行为以 [PRD](../PRD.md) 为准；本规范不改变策略、推荐排序或通知规则。

## 1. 主题原则与实现优先级

- 石墨灰承载信息，冰川蓝强调操作与选择，呼应第一版 Logo 的蓝色眼睛。
- 四个页面共用一套颜色；美股 / 港股、CSP / CC 通过标题与控件区分，不分别建立彩色主题。
- 默认跟随 macOS 浅色 / 深色外观，不要求一期增加独立主题设置。
- 正文、收益数字和表格以中性色为主。绿色不代表“推荐买入”，红色不代表“推荐卖出”。
- 表中颜色均为不透明 sRGB 十六进制色值；不通过给整张卡片降低透明度表达禁用或错误。

**颜色有两类职责，不能混为一谈：**

1. 原生窗口、侧栏、表格选择、输入框、按钮及菜单优先使用系统组件与动态语义颜色。表中的中性色是设计参考，不声称等于某个 `NSColor` 的固定解析值。系统外观、强调色、窗口焦点及辅助功能可以改变实际显示。
2. 自定义卡片、推荐标签、状态标签和需要明确品牌色的区域使用本文件的命名颜色。普通对比度下遵循表中色值；名称表达用途，不按蓝色 / 灰色编号。

如果系统控件与设计稿色值不同，保留系统的可用性和状态反馈；不要为追求截图完全一致而重绘原生控件。

## 2. 基础颜色

“建议资源名”是后续 Assets 的命名约定，当前尚不存在对应 Color Set。系统区域不必创建同义资源。

| 语义 Token | 浅色 | 深色 | 用途 / 建议资源名 |
| --- | --- | --- | --- |
| `surface.window` | `#F5F6F8` | `#1C1D20` | 页面底色；自定义画布可用 `LynxWindow` |
| `surface.sidebar` | `#ECEEF2` | `#25262A` | 侧栏参考底色；自定义区域可用 `LynxSidebar` |
| `surface.card` | `#FFFFFF` | `#2C2D32` | 内容卡片，`LynxCard` |
| `surface.subtle` | `#F7F9FC` | `#30333A` | 表头、展开子行、次级分组，`LynxSubtle` |
| `surface.input` | `#FFFFFF` | `#24262B` | 自定义输入背景参考，`LynxInput` |
| `text.primary` | `#20242C` | `#F2F3F5` | 标题、标的代码、关键数值；优先 `.primary` |
| `text.secondary` | `#626B78` | `#A9B0BC` | 说明、时间、表头；优先 `.secondary` |
| `text.disabled` | `#8A919C` | `#767D89` | 不可用控件参考；交由 `.disabled(true)` |
| `border.separator` | `#E2E5EB` | `#40434B` | 卡片与行分隔，`LynxSeparator` |
| `border.control` | `#818B99` | `#858E9C` | 必须靠边界识别的自定义控件，`LynxControlBorder` |
| `accent.interactive` | `#0067D9` | `#6AA9FF` | 链接、焦点、强调图标，`LynxAccent` |

普通分隔线用于组织信息，不承担输入框可操作性或键盘焦点提示。需要这些含义时用系统边框 / 焦点环，或使用更清楚的 `border.control` / `accent.interactive`。

## 3. 选择、推荐与按钮

| 语义 Token | 浅色 | 深色 | 用途 / 建议资源名 |
| --- | --- | --- | --- |
| `interaction.hover` | `#F0F5FC` | `#303B4B` | 自定义可操作项悬停，`LynxHover` |
| `interaction.selectedBackground` | `#E8F1FF` | `#233B59` | 自定义侧栏选中、推荐标签底色，`LynxSelectionBackground` |
| `interaction.selectedForeground` | `#005BC0` | `#8ABEFF` | 上述底色内的文字与图标，`LynxSelectionForeground` |
| `button.primaryBackground` | `#0067D9` | `#0A64D4` | 自定义主按钮填充，`LynxPrimaryButton` |
| `button.primaryHovered` | `#005CC4` | `#0B5BBF` | 自定义主按钮悬停，`LynxPrimaryButtonHover` |
| `button.primaryPressed` | `#0052AD` | `#084FA8` | 自定义主按钮按下，`LynxPrimaryButtonPressed` |
| `button.onPrimary` | `#FFFFFF` | `#FFFFFF` | 自定义主按钮上的文字 / 图标，`LynxOnPrimary` |
| `interaction.inactiveSelection` | `#E3E6EB` | `#3A3D44` | 自定义选择在窗口失焦后的参考底色，`LynxInactiveSelection` |

### 3.1 状态规则

- 普通侧栏：主文字色，SF Symbols 与文字同色。选中：浅蓝底与选中文字色。原生侧栏由系统管理选择样式，允许其使用系统强调色。
- 普通行：保持卡片底色。仅可点击的自定义行显示悬停底色；鼠标经过不代表选中。
- 选中优先于悬停；键盘焦点仍有独立焦点环，不用颜色替代焦点状态。原生控件不手写状态判断。
- 失焦窗口中的原生选择和控件由系统弱化。自定义选择使用失焦底色与主文字色，不继续模拟活跃焦点；推荐标签表示排名，不随窗口失焦变成“未推荐”。
- 次按钮使用原生 `.bordered` 样式；主按钮优先 `.borderedProminent`，避免每个操作都使用实心蓝。
- 禁用用 `.disabled(true)`。旁边用正常次要文字解释原因；不要把错误原因也降为禁用灰。
- 加载保留按钮占位和可读文字，使用 `ProgressView` 与“刷新中…”；防重复触发由行为逻辑控制。

### 3.2 深色按钮的特殊约束

`#6AA9FF` 用于深色底上的链接与图标，不直接拿它作为白字实心按钮背景。自定义白字按钮使用 `#0A64D4`，保证文字对比度。原生按钮使用系统样式和前景处理；不要对整个按钮强制 `.foregroundStyle(.white)` 后假设所有系统状态均可读。

## 4. 状态颜色

| 语义 Token | 浅色 | 深色 | 建议资源名 |
| --- | --- | --- | --- |
| `status.successForeground` | `#237347` | `#7DD7A4` | `LynxSuccess` |
| `status.successBackground` | `#EAF6EE` | `#203A2C` | `LynxSuccessBackground` |
| `status.warningForeground` | `#8A5700` | `#E8BD6A` | `LynxWarning` |
| `status.warningBackground` | `#FFF3D9` | `#41341F` | `LynxWarningBackground` |
| `status.errorForeground` | `#B42332` | `#FF9AA5` | `LynxError` |
| `status.errorBackground` | `#FDEDEF` | `#472A31` | `LynxErrorBackground` |

| 状态 | 展示规则 |
| --- | --- |
| 已连接 / 检查通过 | 成功色图标＋明确文字，不给整页染绿 |
| 休市 / 定时刷新关闭 | 次要文字色，属于正常状态 |
| 刷新中 | 系统进度指示＋文字；保留旧结果及上次成功时间 |
| 待设置 | 警告色＋缺少的具体参数＋配置入口 |
| 旧数据 / 本轮数据不完整 | 警告色＋时间和原因；不当作推荐变化 |
| 连接失败 / 本轮刷新失败 | 错误色描述故障；保留的旧结果另标警告，不整表变红 |
| 无合格候选 | 中性空状态＋筛选原因；不是系统错误 |
| 未知 / 无法计算 | 次要文字与“不可用”及原因；不显示为零、不套成功色 |
| 模拟 / 一期候选 | 中性标签：`surface.subtle`＋`text.secondary` |

信息提示使用强调蓝或中性色；没有必要新增另一套信息紫。任何状态均须有文字，必要时加符号，不能仅用色点传达。

## 5. 四个页面的用色分工

### 5.1 期权

- 美股 / 港股使用原生分段选择器；CSP / CC 卡片共用背景和标题层级。
- 默认每股票一条最佳合约；展开候选用 `surface.subtle`，保留缩进与展开箭头，不能只靠底色区分。
- “推荐 1 / 2 / 3”使用选择前景 / 背景的蓝色小标签，避免整行蓝底干扰表格比较。推荐身份与用户当前选中行是两个不同概念。
- 净权利金、持有期收益率、年化收益率保持主文字色和等宽数字。折价与上行空间不自动套红绿；年化不通过高饱和色取得更高优先级。
- 上次成功时间采用次要文字；旧数据增加警告文字。每个市场的状态独立呈现。
- “距上次推荐变化”的含义仍待确认，主题规范不替它新增涨跌颜色或计算口径。

### 5.2 配置

- 表格、展开高级参数与期权页面复用相同层级。
- 原生开关和输入框保留系统状态；参数输入不以红绿暗示收益好坏。
- 参数错误：系统或明确的错误边界，加错误文字；缺少必填参数：待设置警告。不要让一个方向的错误把另一个方向的整张卡片染成错误色。
- “添加股票”可作为主按钮；恢复默认、展开参数为次级操作。

### 5.3 AI 集成

- Codex 与 Claude Code 使用同样的中性卡片，不给两个 Agent 分配竞争性的主题色。
- 安装使用主操作样式；卸载采用次操作 / 适当的破坏性操作语义，不默认大面积红色。
- 安装状态使用文字＋成功或中性色；不可把设计预览中的状态描述成已安装。

### 5.4 设置

- 采用原生分组表单、开关、菜单与文本框。
- 连接状态使用状态色；通知关闭、登录启动关闭均是正常中性状态。
- 关键解释与权限说明使用次要文字，不能用禁用灰降低可读性。

## 6. SwiftUI / AppKit 语义映射

以下 API 是实现方向，不表示已在项目最低 macOS 版本上验证。最低版本仍待确认，示例不据此设定部署目标。

| 设计语义 | SwiftUI / AppKit 建议 | 与固定色值的关系 |
| --- | --- | --- |
| 标题、正文、数值 | `.foregroundStyle(.primary)` / `Color(nsColor: .labelColor)` | 系统动态色，不保证等于 `text.primary` |
| 说明、时间、表头 | `.foregroundStyle(.secondary)` / `Color(nsColor: .secondaryLabelColor)` | 系统动态色，不保证等于 `text.secondary` |
| 窗口背景 | `Color(nsColor: .windowBackgroundColor)` | 系统窗口表面；自定义画布需要精确配色时使用 `LynxWindow` |
| 侧栏 | `NavigationSplitView` 配合 `List` / `.listStyle(.sidebar)` | 侧栏材质、活跃选择和失焦由系统管理；没有一个固定 NSColor 能完整替代它 |
| 自定义卡片 | `Color("LynxCard")` | 按 Assets 外观返回规定值；系统分组表单保留系统表面 |
| 文本输入背景 | 原生 `TextField`；必要时 `Color(nsColor: .textBackgroundColor)` | 由系统处理输入与焦点，不要求等于 `surface.input` |
| 表头 / 子行底色 | `Color("LynxSubtle")`；原生 `Table` 保留其默认行样式 | 用于自定义分组，不覆盖系统选择 |
| 分隔线 | `Divider()` / `Color(nsColor: .separatorColor)` | 系统动态分隔；自定义卡片可用 `LynxSeparator` |
| 默认强调色 | Assets 的 `AccentColor`，与 `accent.interactive` 对应 | 在工程中配置默认强调色；允许原生组件遵循用户的系统强调色偏好 |
| 自定义链接 / 品牌强调 | `Color("LynxAccent")`，局部 `.tint(...)` | 需要明确冰川蓝的自定义内容使用；不向整个原生窗口强制注入品牌 tint |
| 原生主 / 次按钮 | `.buttonStyle(.borderedProminent)` / `.buttonStyle(.bordered)` | 系统负责按下、禁用及前景；品牌资源用于确需自定义的按钮 |
| 原生开关 / 进度 | `Toggle` / `ProgressView` | 跟随系统控件；不重画控件轨道或改变业务状态含义 |
| 原生表格 / 列表选择 | `Table(selection:)` / `List(selection:)` | 系统负责活跃、失焦、多选与文字对比；不要再覆盖自定义选中底色 |
| 自定义选择 / 推荐标签 | `LynxSelectionBackground`＋`LynxSelectionForeground` | 用表中配对色；推荐标签不参与列表 selection |
| 成功 / 警告 / 错误标签 | `LynxSuccess` / `LynxWarning` / `LynxError` 及各自背景 | 自定义语义资源；`.green` / `.orange` / `.red` 不等于此规范的精确色值 |
| 禁用 | `.disabled(true)` | 让系统表达禁用，不统一施加 `.opacity(0.5)` |
| 键盘焦点 | 系统焦点机制，按实际需要使用 `@FocusState` | 保留系统焦点环，不能用永久蓝边模拟焦点 |
| 破坏性操作 | `Button(role: .destructive)` | 由系统语义决定呈现；实际操作仍遵循确认与权限规则 |

### 6.1 Color Assets 约定

后续工程在其资源目录 `Assets.xcassets` 内定义需要的 `.colorset`；无需为了文档一次性创建全部资源。

- `Any Appearance` 填浅色色值，`Dark` 填深色色值；颜色空间选择 sRGB，Alpha 为 1。
- 工程默认强调色资源为 `AccentColor`；构建设置 `ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME` 指向 `AccentColor`。`LynxAccent` 保留为自定义内容的明确品牌颜色，两者普通模式色值保持一致。
- 应用图标属于 `AppIcon.appiconset`，与 Color Set 分开；本规范不修改第一版 Logo，也不为它生成自动反色版本。
- 不在 View 中散落十六进制字面量、按当前外观手写三元色值，或把动态颜色转换成一次性的 RGB 常量。
- 不为主题单独引入第三方依赖。

### 6.2 示例：原生操作与自定义推荐标签

下列片段说明映射方式，需在后续工程创建相应 Color Assets 后使用；不是当前可运行的 App 实现。

```swift
import SwiftUI

enum LynxTheme {
    static let accent = Color("LynxAccent")
    static let selectionBackground = Color("LynxSelectionBackground")
    static let selectionForeground = Color("LynxSelectionForeground")
}

struct RecommendationBadge: View {
    let rank: Int
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Text("推荐 \(rank)")
            .font(.caption)
            .foregroundStyle(
                contrast == .increased
                    ? Color.primary
                    : LynxTheme.selectionForeground
            )
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                RoundedRectangle(cornerRadius: 4)
                    .fill(LynxTheme.selectionBackground)
            }
            .overlay {
                if contrast == .increased {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color.primary, lineWidth: 1)
                }
            }
    }
}

// 在实际 View 中使用；操作由应用层提供。
struct RefreshAction: View {
    let isRefreshing: Bool
    let refresh: () -> Void

    var body: some View {
        Button(action: refresh) {
            Text(isRefreshing ? "刷新中…" : "立即刷新")
        }
        .buttonStyle(.bordered)
        .disabled(isRefreshing)
    }
}
```

示例没有全局强制外观或按钮前景；`RefreshAction` 不负责定义刷新调度规则。

## 7. 可访问性与对比度

### 7.1 普通模式的静态配对检查

下表采用 WCAG 相对亮度公式检查不透明 sRGB 色值，小字号文字以至少 4.5:1 为设计目标。它只验证表中配对，不代表已验证原生 App、材质混合、所有交互状态或辅助功能合规。

| 前景 / 背景 | 浅色对比度 | 深色对比度 |
| --- | --- | --- |
| 主文字 / 浅色窗口、深色卡片 | 14.38:1 | 12.37:1 |
| 次要文字 / 展开子行 | 5.11:1 | 5.80:1 |
| 强调蓝 / 卡片 | 5.33:1 | 5.71:1 |
| 白字 / 自定义主按钮 | 5.33:1 | 5.55:1 |
| 选中文字 / 选中背景 | 5.67:1 | 5.91:1 |
| 成功文字 / 成功背景 | 5.23:1 | 7.12:1 |
| 警告文字 / 警告背景 | 5.54:1 | 6.87:1 |
| 错误文字 / 错误背景 | 5.74:1 | 6.34:1 |

禁用文字不用于承载必须阅读的信息。淡分隔线不是交互边界；自定义控件边界和焦点提示以至少 3:1 为检查目标，实际实现仍须检查。

### 7.2 系统辅助功能

- 增强对比度：读取 `@Environment(\.colorSchemeContrast)`。原生区域由系统响应；自定义标签优先切换到主文字色，并增加清楚的边界，保留“成功 / 失败 / 推荐”等文字和图标。不要把普通模式色表声称为已验证的高对比度方案。
- 减少透明度：通过 `@Environment(\.accessibilityReduceTransparency)` 响应。系统侧栏与材质优先采用系统处理；若自定义表面使用材质，开启时退回对应的不透明表面色。
- 区别于颜色：通过 `@Environment(\.accessibilityDifferentiateWithoutColor)` 获取偏好。所有模式都保留状态文字与符号，不把基本可理解性建立在用户开启此设置之后。
- 无障碍标签描述真实状态；装饰性色点和图标避免重复朗读。推荐序号、子行关系、禁用原因都应有文字或适当的辅助功能表达。
- 原生按钮、菜单、选择器保留键盘与系统焦点行为；自定义可交互区域需要明确焦点反馈。

## 8. 后续实现验收

本清单用于后续 App 实现，当前没有进行产品测试。

- 浅色 / 深色覆盖四个页面、展开子行、参数编辑、弹窗、空状态、刷新中和连接故障。
- 运行中切换系统外观，各语义颜色同步变化；没有残留硬编码白底、黑字或亮蓝底白字低对比区域。
- 系统强调色、窗口失焦、键盘焦点、多选及禁用状态维持原生行为。
- 核对所有实际文字 / 背景配对，包含主按钮悬停与按下，以及自定义控件边界；不能只依赖本文件的静态抽样。
- 开启增强对比度、减少透明度和区别于颜色后，状态、层级、选择及焦点仍能辨认。
- 数据刷新失败时，旧结果、时间与故障原因同时可读；一个市场失败不把另一市场染成故障状态。
- 推荐标签不等于用户选中；收益率正值不自动变绿；缺失值不当零；年化不被视觉强化为排序依据。
- HTML 预览和 SwiftUI 实现采用同一语义角色，但不要求 Web 与系统材质逐像素一致。

## 9. 待实现事项

后续在实际 macOS 工程中创建所需 Color Assets、应用语义映射，并更新页面预览。部署目标确定后，核验 API 可用性、实际控件呈现及辅助功能状态；本规范不代表这些实现已经完成。
