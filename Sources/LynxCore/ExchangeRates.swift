import Foundation

// Same public quote source as the reviewed OM baseline; no account or holdings query.
public enum ExchangeRates {
    public static func fetch(now: Date = Date()) async throws -> [Market: Double] {
        var request = URLRequest(url: URL(string: "https://qt.gtimg.cn/q=whUSDCNY,whHKDCNY")!)
        request.timeoutInterval = 10
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AnalysisError.message("汇率服务不可用") }
        return parse(String(decoding: data, as: UTF8.self), now: now)
    }
    public static func parse(_ text: String, now: Date) -> [Market: Double] {
        var result: [Market: Double] = [:]
        for line in text.components(separatedBy: .newlines) {
            for (market, pair) in [(Market.us, "USDCNY"), (.hk, "HKDCNY")] where line.hasPrefix("v_wh\(pair)=\"") {
                let fields = line.components(separatedBy: "\"").dropFirst().first?.components(separatedBy: "~") ?? []
                guard fields.count > 5, fields[2] == pair, let rate = Double(fields[3]), rate.isFinite, rate > 0,
                      let date = MarketDate.formatter(.hk, format: "yyyyMMddHHmmss").date(from: fields[5]), usable(date, at: now) else { continue }
                result[market] = rate
            }
        }
        return result
    }
    // CFETS session/2026 holiday policy, matching the fixed OM baseline. Unknown years fail closed.
    static func usable(_ quoted: Date, at now: Date) -> Bool {
        guard quoted <= now, MarketDate.day(now, market: .hk).hasPrefix("2026-") else { return false }
        let f = MarketDate.formatter(.hk, format: "yyyy-MM-dd HH:mm:ss")
        func working(_ day: String) -> Bool {
            let closures = [("01-01","01-03"),("02-15","02-23"),("04-04","04-06"),("05-01","05-05"),("06-19","06-21"),("09-25","09-27"),("10-01","10-07")]
            guard let d = f.date(from: day + " 12:00:00") else { return false }
            var c = Calendar(identifier: .gregorian); c.timeZone = f.timeZone
            let weekday = c.component(.weekday, from: d), md = String(day.suffix(5))
            return day.hasPrefix("2026-") && weekday != 1 && weekday != 7 && !closures.contains { md >= $0.0 && md <= $0.1 }
        }
        func latest(_ date: Date) -> Date? {
            var day = MarketDate.day(date, market: .hk)
            for _ in 0..<370 {
                if working(day), let start = f.date(from: day + " 09:30:00"), start <= date { return start }
                guard let previous = MarketDate.adding(-1, to: day, market: .hk) else { return nil }; day = previous
            }
            return nil
        }
        guard let session = latest(quoted), quoted < session.addingTimeInterval(17.5 * 3600), latest(now) == session else { return false }
        if now < session.addingTimeInterval(17.5 * 3600) { return now.timeIntervalSince(quoted) <= 86400 }
        var day = MarketDate.adding(1, to: MarketDate.day(session, market: .hk), market: .hk)!
        while day <= MarketDate.day(now, market: .hk) {
            if !working(day) { return true }
            day = MarketDate.adding(1, to: day, market: .hk)!
        }
        return now.timeIntervalSince(quoted) <= 86400
    }
}
