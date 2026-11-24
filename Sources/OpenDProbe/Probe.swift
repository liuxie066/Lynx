import Foundation
import LynxCore

@main struct Probe {
    static func main() async {
        do {
            let args = Array(CommandLine.arguments.dropFirst())
            if args == ["--help"] { print(usage); return }
            var port: UInt16 = 11111
            var market: Market?
            var symbol: String?
            var fullScan = false
            var index = 0
            while index < args.count {
                guard index + 1 < args.count else { throw UsageError() }
                let value = args[index + 1]
                switch args[index] {
                case "--port":
                    guard let parsed = UInt16(value), parsed > 0 else { throw UsageError() }
                    port = parsed
                case "--market":
                    guard let parsed = Market(rawValue: value) else { throw UsageError() }
                    market = parsed
                case "--symbol": symbol = value
                case "--scan": guard value == "true" else { throw UsageError() }; fullScan = true
                default: throw UsageError()
                }
                index += 2
            }
            guard (market == nil) == (symbol == nil) else { throw UsageError() }
            if fullScan {
                guard let market, let symbol else { throw UsageError() }
                var stock = try WatchStock(market: market, code: symbol)
                stock.cc.enabled = true; stock.cc.minDTE = "7"; stock.cc.maxDTE = "14"
                let outcome = try await BrokerScanner(port: port).scan(market: market, stocks: [stock])
                switch outcome {
                case .closed(let reason): print(reason)
                case .result(let result):
                    print("Market: \(market.rawValue), complete: \(result.complete), checked: \(result.completedAt.ISO8601Format())")
                    for item in result.stocks {
                        print("\(item.stock.code) \(item.strategy.rawValue): \(item.candidates.count) candidates, incomplete: \(item.incomplete)")
                        for reason in item.reasons.prefix(12) { print(reason) }
                    }
                    if !result.complete { exit(2) }
                }
                return
            }
            let mode: ProbeMode = if let market, let symbol { .options(market: market, code: symbol) } else { .handshake }
            let report = try await OpenDClient(port: port).probe(mode)
            print("OpenD handshake: OK, server version \(report.serverVersion)")
            print("Checked: \(report.checkedAt.ISO8601Format())")
            for (index, snapshot) in report.snapshots.enumerated() {
                print("Security: \(snapshot.basic.security.market).\(snapshot.basic.security.code), price: \(text(snapshot.basic.curPrice)), updated: \(snapshot.basic.updateTime ?? "unknown")")
                if let option = snapshot.optionExData {
                    print("  bid=\(text(snapshot.basic.bidPrice)) ask=\(text(snapshot.basic.askPrice)) strike=\(text(option.strikePrice)) expiry=\(option.strikeTime ?? "unknown")")
                    print("  raw contractSize=\(option.contractSize.map(String.init) ?? "unknown") contractSizeFloat=\(text(option.contractSizeFloat)) contractMultiplier=\(text(option.contractMultiplier)) ownerLotMultiplier=\(text(option.ownerLotMultiplier))")
                }
                if index > 0 { print("  missing fields: \(snapshot.missingOptionFields.joined(separator: ", "))") }
            }
            for note in report.notes { print(note) }
        } catch {
            FileHandle.standardError.write(Data((error.localizedDescription + "\n").utf8))
            exit(1)
        }
    }
    static func text(_ value: Double?) -> String { value.map { String($0) } ?? "unknown" }
    static let usage = "Usage: lynx-opend-probe [--port 11111] [--market us|hk --symbol AAPL|00700] [--scan true]\nDefault: loopback handshake only. --scan true explicitly runs a one-stock CC scan for 7–14 DTE including public FX, calendars and history. Market + symbol explicitly request one bounded option sample."
    struct UsageError: LocalizedError { var errorDescription: String? { Probe.usage } }
}
