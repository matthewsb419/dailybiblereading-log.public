import Foundation

/// A calendar day as the website writes it: "2026-10-14". Plain strings sort in date order,
/// which the scoring relies on, exactly like the web version.
public typealias DayKey = String

/// Calendar arithmetic on day keys in one time zone, plus the clock ("now") the log runs on.
public struct Days: Sendable {
    public var calendar: Calendar
    public var now: Date

    public init(now: Date = Date(), timeZone: TimeZone = .current) {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = timeZone
        c.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = c
        self.now = now
    }

    public var today: DayKey { key(now) }
    public var yesterday: DayKey { shift(today, -1) }

    public func key(_ d: Date) -> DayKey {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return Days.make(c.year!, c.month!, c.day!)
    }
    public static func make(_ y: Int, _ m: Int, _ d: Int) -> DayKey {
        String(format: "%04d-%02d-%02d", y, m, d)
    }
    public static func parts(_ k: DayKey) -> (y: Int, m: Int, d: Int) {
        let p = k.split(separator: "-").map { Int($0) ?? 0 }
        return (p.count > 0 ? p[0] : 0, p.count > 1 ? p[1] : 1, p.count > 2 ? p[2] : 1)
    }
    public func date(_ k: DayKey) -> Date {
        let p = Days.parts(k)
        return calendar.date(from: DateComponents(year: p.y, month: p.m, day: p.d))!
    }
    public func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        // like JS `new Date(y, m-1, d)`: out-of-range days roll into the neighbouring month
        let first = calendar.date(from: DateComponents(year: y, month: m, day: 1))!
        return calendar.date(byAdding: .day, value: d - 1, to: first)!
    }
    public func shift(_ k: DayKey, _ n: Int) -> DayKey {
        key(calendar.date(byAdding: .day, value: n, to: date(k))!)
    }
    /// 0 = Sunday … 6 = Saturday, as JS getDay().
    public func weekday(_ k: DayKey) -> Int { calendar.component(.weekday, from: date(k)) - 1 }
    public func daysInMonth(_ y: Int, _ m: Int) -> Int {
        calendar.range(of: .day, in: .month, for: date(y, m, 1))!.count
    }
    /// Whole days from a to b (b − a).
    public func between(_ a: DayKey, _ b: DayKey) -> Int {
        calendar.dateComponents([.day], from: date(a), to: date(b)).day!
    }
    /// Calendar days from…to inclusive, optionally only one weekday (0 = Sunday).
    public func count(_ from: DayKey, _ to: DayKey, weekday wd: Int? = nil) -> Int {
        guard from <= to else { return 0 }
        let n = between(from, to) + 1
        guard let wd = wd else { return n }
        let first = weekday(from)
        let offset = (wd - first + 7) % 7
        return offset >= n ? 0 : (n - 1 - offset) / 7 + 1
    }
    /// Every day key from…to inclusive.
    public func range(_ from: DayKey, _ to: DayKey) -> [DayKey] {
        guard from <= to else { return [] }
        return (0...between(from, to)).map { shift(from, $0) }
    }

    /// Timestamps in the website's format (`toISOString`), which sort as strings.
    public func stamp() -> String { Days.iso.string(from: now) }
    nonisolated(unsafe) static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    // display
    public func pretty(_ k: DayKey) -> String { format(k, "EEEE, MMMM d") }
    public func short(_ k: DayKey) -> String { format(k, "MMM d") }
    public func monthName(_ y: Int, _ m: Int) -> String { format(Days.make(y, m, 1), "MMMM yyyy") }
    public func monthShort(_ y: Int, _ m: Int) -> String { format(Days.make(y, m, 1), "MMM yyyy") }
    public func format(_ k: DayKey, _ pattern: String) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = Locale(identifier: "en_US")
        f.setLocalizedDateFormatFromTemplate(pattern)
        return f.string(from: date(k))
    }
}

/// Number formatting that matches the website's text exactly.
public enum Fmt {
    /// `Math.round(n).toLocaleString("en-US")`
    public static func n(_ x: Double) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US")
        f.numberStyle = .decimal
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: jsRound(x))) ?? "\(Int(jsRound(x)))"
    }
    /// 1.2M / 15K / 640
    public static func compact(_ x: Double) -> String {
        if x >= 999_500 { return trim(jsRound(x / 1e5) / 10) + "M" }
        return x >= 1000 ? "\(Int(jsRound(x / 1000)))K" : "\(Int(jsRound(x)))"
    }
    /// JS `toFixed`: halves round up, unlike printf.
    public static func fixed(_ x: Double, _ digits: Int) -> String {
        let p = pow(10.0, Double(digits))
        let r = (x * p).rounded(.toNearestOrAwayFromZero) / p
        return String(format: "%.\(digits)f", r)
    }
    /// JS `Math.round`: halves go up (toward +∞).
    public static func jsRound(_ x: Double) -> Double { (x + 0.5).rounded(.down) }
    static func trim(_ x: Double) -> String {
        x == x.rounded() ? "\(Int(x))" : "\(x)"
    }
}
