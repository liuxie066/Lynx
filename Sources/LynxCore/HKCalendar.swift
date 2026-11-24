import Foundation

// Public HKEX CT/077/26 schedule, same fixed dataset as the reviewed OM baseline.
// Half-days count as one close-to-close RV session. This is not an expiry calendar.
public enum HKCalendar {
    public static let source = "https://www.hkex.com.hk/Services/Circulars-and-Notices/Participant-and-Members-Circulars/SEHK/2026/SEHK_CT_077_2026Jun01162846?sc_lang=en"
    public static let dataset = "HKEX_CT07726_2027_v1"
    public static func schedule2027() -> [String: Int] {
        let holidays = Set(["01-01", "02-08", "02-09", "03-26", "03-29", "04-05", "05-13", "06-09", "07-01", "09-16", "10-01", "10-08", "12-27"])
        let halfDays = Set(["02-05", "12-24", "12-31"])
        let f = MarketDate.formatter(.hk)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = f.timeZone
        var day = "2027-01-01", result: [String: Int] = [:]
        while day <= "2027-12-31" {
            let weekday = calendar.component(.weekday, from: f.date(from: day)!)
            let suffix = String(day.suffix(5))
            if weekday != 1 && weekday != 7 && !holidays.contains(suffix) { result[day] = halfDays.contains(suffix) ? 1 : 0 }
            day = MarketDate.adding(1, to: day, market: .hk)!
        }
        return result
    }
    public static func agrees(provider: [String: Int], schedule: [String: Int]) -> Bool {
        provider.allSatisfy { day, type in
            guard let expected = schedule[day] else { return false }
            return type == 0 ? expected == 0 : [1,2].contains(type) && expected == 1
        }
    }
}
