# Lynx

options monitor for mac

Lynx（猞猁）是全 Swift 的本地 macOS 期权监控 App，面向 Apple Silicon，使用用户自行登录的富途 / moomoo OpenD，分析港股、美股的 CSP 和 CC 机会。

**当前为一期开发版。** 已接通原生界面、行情扫描、策略计算、后台刷新、本地保存和 AI 操作入口。已完成美股 OpenD 实连及离线自动化检查；验收情况和已知限制见 [开发与验证](docs/DEVELOPMENT.md)。当前以 macOS 14 / arm64 编译，本地 ad-hoc 签名，尚非公证分发版本。

## 功能

- 期权页切换美股 / 港股，CSP、CC 两张表展示每股票最佳合约；各列表最多取前三，行尾展开其余合格合约，查看筛选原因。
- 展示每手净权利金、持有期 / 年化收益、行权价、到期日、接货折价 / 上行空间、担保现金 / 股数，以及推荐排名变化。
- 独立配置每股票的 CSP / CC、行权价、DTE 和高级门槛；可恢复默认。CSP 需填接货最高价；CC 不填写持仓成本。
- 手动刷新，或关闭 / 10 分钟 / 30 分钟 / 1 小时定时刷新。两市场分别判开休市，共用一轮任务，不重入、不排队；失败保留历史结果。
- 关闭窗口留在菜单栏；睡眠停止请求，唤醒按到期状态处理。可选登录启动、推荐变化通知与连接异常通知，默认均关闭。
- 配置、最近结果和通知基线本地保存，无开发者服务器或云同步。
- 为 Codex、Claude Code 安装、更新和卸载 Lynx 技能，通过正在运行的 App 读取结果和修改设置；不直接编辑存储文件。

## 边界与计算

只做行情与一手期权分析，不读取账户、现金、持仓或账本，不交易、不代管 OpenD。合约股数来自期权链与快照并核对一致，不能默认 100。CSP 展示担保现金；CC 按“当前股价 × 真实一手股数”计算收益率，均不证明真实资产足够。

适用 OM 规则按固定基线移植：持有期收益率以 0.002 为档宽、档首为锚，年化不主导排序；去掉账户容量、集中度及 CC 成本门槛。费用、IV/RV、财报日历或必要行情不完整时明确标注，不以未知值代替零。详见 [规则与数据口径](docs/STRATEGY.md)。

费用按 Futu HK 的港美期权模型估算，不支持用户修改；不同 moomoo 地区未逐一核验。CNY 门槛使用腾讯公开汇率，直接从数据源读取。行情数据仍受其提供方使用条款约束。

## AI 能力

| 已纳入一期 | 行为 |
| --- | --- |
| 推荐与解释 | 共用页面结果、其他合格合约、排名、筛选原因、参数和时间 |
| 关注与策略 | 添加 / 移除股票，开关 CSP / CC，修改或恢复参数 |
| App 设置 | 端口、刷新、通知、登录启动；系统权限仍走 macOS 流程 |
| 状态与刷新 | 读取实际状态；主动刷新共用任务，启动不代表成功 |

名称识别在添加关注时内部完成，不单列 Agent 工具；匹配不唯一时返回候选代码。临时查询、临时条件筛选、MCP、自有聊天 Bot 和历史运行中心未纳入一期。技能安装不等于客户端安装或登录，客户端发现技能可能需要重开会话。

## 开发

打开 [Lynx.xcodeproj](Lynx.xcodeproj)，或在完整 Xcode 工具链下运行：

~~~sh
bash scripts/test.sh
bash scripts/build-app.sh
open build/Xcode/Build/Products/Debug/Lynx.app
~~~

SwiftUI、Foundation、AppKit、UserNotifications 和 ServiceManagement；无第三方运行时或 Python 子进程。OpenD 由用户自装、登录、升级，默认只连本机 11111 端口。

- [PRD](docs/PRD.md)
- [开发、验证及 CLI](docs/DEVELOPMENT.md)
- [计算规则](docs/STRATEGY.md)
- [冰川蓝主题](docs/designs/theme-colors.md)

## 许可证

[MIT](LICENSE)，Copyright © 2026 liuxie066。OM 规则移植的来源与原许可见 [ThirdPartyNotices](ThirdPartyNotices.md)；MIT 不覆盖第三方行情数据及其条款。
