# 开发与验证

## 工程

Lynx.xcodeproj 是原生 macOS App，共享 Lynx scheme；Package.swift 用于核心、App 和只读 probe 的编译与测试。Swift 6，无第三方运行时，无 Python 子进程。

| 位置 | 职责 |
| --- | --- |
| Sources/LynxApp | 四页 SwiftUI、AppStore、菜单栏、系统通知 / 登录项、Agent 业务入口和技能安装 |
| Sources/LynxCore | 配置、数据证据、策略 / 费用 / 排序、OpenD 只读适配、汇率、Unix socket 传输 |
| Sources/OpenDProbe | 显式运行的只读连接 / 样本 / 扫描验证 |
| macOS/Assets.xcassets | AppIcon 与透明品牌标记 |
| Tests/LynxCoreTests | 固定向量、假服务、异常、保存、刷新状态、Agent 和技能文件隔离测试 |

## 构建

当前目标 macOS 14、Apple Silicon arm64；最低系统的跨版本兼容性仍需验证。

~~~sh
bash scripts/test.sh
bash scripts/build-app.sh
open build/Xcode/Build/Products/Debug/Lynx.app
~~~

Xcode 在其他磁盘时，通过当前终端的 DEVELOPER_DIR 指向该 Xcode 的 Contents/Developer，无须改全局 xcode-select。AppIcon 由资产目录配置，采用本地 ad-hoc 签名，不是公证分发包。无需创建 Release 才能本地运行。

只有命令行工具时可用备用构建，但它不替代 actool 验收：

~~~sh
bash scripts/build-app.sh --swiftpm
open build/Lynx.app
~~~

离线界面预览显式使用 --preview；不读写真实配置、不连接 OpenD、不开放 Agent 入口。展示数据不是行情或计算证据。

~~~sh
open -n build/Xcode/Build/Products/Debug/Lynx.app --args --preview
~~~

功能验收可用 --data-directory 指定独立目录。一次只运行一个提供 Agent 入口的 App，避免将命令发给另一实例；正常启动不预置任何股票。

## 保存、刷新和系统功能

配置和最近结果以 Codable JSON 原子保存于当前用户 Application Support 的 Lynx 目录。坏配置、未知版本、重复或非标准股票代码会阻止覆盖原配置；坏结果文件也保留并提示，配置本身仍可编辑。手工修复文件后重新启动恢复保存。

保存每股票的两个方向、输入草稿、高级参数、端口、刷新与通知偏好，以及每市场结果 / 参数 / 时间 / 基线。启动先显示历史结果；只有自动刷新开启且到期才检查市场，休市不取新期权快照。设置变化取消旧扫描并使对应市场基线失效。单个失败不清除其他市场结果，价格变化不触发推荐通知。

单轮任务串行处理两市场，不重入、不排队。OpenD 请求分协议限频、每请求 15 秒超时并定期保活；取消会关闭自有连接。睡眠取消请求，唤醒按到期状态处理。退出不停止 OpenD。关闭窗口留菜单栏，首次关窗提醒。登录项使用 SMAppService；通知使用 UNUserNotificationCenter，只有开启开关时申请权限。

费用与数据边界见 [STRATEGY](STRATEGY.md)。日历未知年份、未核实地区费用、权限不足均不能冒充已支持；2026 汇率会话日历需要在下一年度随 App 维护更新。

## AI 本地入口

App 可执行文件同时提供 --agent JSON 命令模式，不另装 Python、后台服务或 MCP。示例中的路径应换成正在运行 App 的实际位置：

~~~sh
Lynx.app/Contents/MacOS/Lynx --agent '{"command":"list","arguments":{}}'
Lynx.app/Contents/MacOS/Lynx --agent '{"command":"recommendations","arguments":{"market":"us","strategy":"CC"}}'
Lynx.app/Contents/MacOS/Lynx --agent '{"command":"strategy.set","arguments":{"market":"us","symbol":"AAPL","strategy":"CC","enabled":"true"}}'
~~~

传输使用当前用户私有目录中的 Unix socket，校验对端用户，带独占入口锁；没有 TCP / HTTP 监听。CLI 与界面共享 AppStore，不直接改 JSON。结果含 ok、实际数据或错误；失败返回非零，写入错误同时返回实际配置。写入超时是结果未知，应先读状态，不盲目重复写。

能力：list、status、recommendations、explain、watch.add、watch.remove、strategy.set、strategy.reset、settings.set、refresh。参数均为字符串，布尔值 true / false；市场 us / hk，方向 CSP / CC。具体参数由随 App 管理的 SKILL.md 说明。主动刷新返回任务启动 / 共用状态，不能当作扫描成功。

Codex 技能放在用户 .agents/skills/lynx，Claude Code 放在 .claude/skills/lynx。仅用户点击安装 / 更新后写入。卸载只删除带 Lynx 管理标记的技能文件，不覆盖其他技能或客户端配置；存在非托管同名目录时拒绝。技能记录 App 可执行路径，移动 App 后应更新。客户端检测只检查标准 CLI 路径，不检查账户或登录。

## OpenD 验证

用户自行登录官方 OpenD，默认本机 11111。仅支持本机未加密 JSON 接入，不修改 OpenD 配置。协议使用 44-byte FT little-endian 帧、format 1、SHA-1 校验；packetEncAlgo -1 为 None，0 是旧式加密。

~~~sh
swift run lynx-opend-probe
swift run lynx-opend-probe --market us --symbol AAPL
swift run lynx-opend-probe --market us --symbol AAPL --scan true
~~~

默认只握手；market + symbol 请求最多一个期限、两个合约样本。--scan true 显式做一个股票 CC 7–14 DTE 扫描，包括公开汇率、交易日历、历史日线和财报数据；不修改 App 配置。扫描返回 2 表示数据不完整，0 仍需结合休市 / 候选结果判断。不开账户、不订阅交易、不下单。

只读协议：InitConnect 1001、KeepAlive 1004、历史日线 3103、静态证券 3202、快照 3203、期权链 3209、交易日历 3219、市场状态 3223、到期日 3224、财报日历 3401。交易日历 US 编号为 2，与报价 US 编号 11 不同。参照 [官方文档](https://openapi.futunn.com/futu-api-doc/)。只保留需要的行情字段与版本，不存登录身份或握手密钥。

## 验收记录与限制

2026-11-25，本地 Xcode 27.2 / Swift 6 / arm64：

- 原生 Debug 构建成功，资产目录与图标纳入 App。最终检查次数、签名和文件哈希见本轮 review 记录。
- 自动化测试覆盖 OM 四组固定计算输入、收益分档、CC 跨股票排序、未知数据 / OI、RV / 日历、配置与结果坏文件保护、刷新单任务 / 到期 / 睡眠、两市场失败隔离、通知基线、Agent 错误及技能安装 / 更新 / 卸载。
- OpenD 10.11 真实握手成功；美股 AAPL CC 完整扫描成功，当前无合格候选，原因含 IV/RV 和 Delta 门槛。没有为了展示推荐放宽默认门槛。
- 原生 App 实际通过 Unix socket 完成美股 AAPL / 港股 00700 识别、写配置、触发刷新和回读；第二次刷新明确复用任务。美股成功，港股当时休市，未声称港股开市扫描已验收。
- 桌面工具看到原生窗口，但再次检查时系统报告锁屏；完整视觉和点击验收暂未完成。
- 未为测试而开启用户通知、登录项或写入实际客户端技能目录；通知送达 / 点击、系统登录启动及 Codex / Claude 新会话发现技能仍待人工验收。技能文件生命周期已在独立目录测试。
- 无 Release、公证分发、生产部署、账户读取或交易。原工作区未提交内容保留，工作树交付状态以最终回执为准。

## 原生界面打磨验证

本轮保持四页、市场切换和 CSP / CC 卡片的信息结构，统一控件密度、卡片边界、数字对齐和空状态。大表格仅准备轻量行数据，金额在单元格显示时格式化；同一标的的候选通过索引查找，表格可见高度封顶但不截断数据。AI 安装状态在进入页面、App 激活及安装操作后更新。

PresentationTests 覆盖 100 只股票 / 6,000 条候选的完整性、前三、子行缩进数据关系、非 100 股合约及空表格；计时只测行数据准备，不代表渲染帧率或真实行情扫描耗时。取消股票识别的测试验证：即使提供方在取消后返回成功，也不能继续写入关注列表。

本轮仍受锁屏限制，未声称完成浅色 / 深色截图、原生点击、VoiceOver 和小窗口滚动实机验收；具体构建、测试及审查结果见 docs/reviews 中本轮记录。没有为验证开启通知或登录项，也未读取账户或请求新行情。
