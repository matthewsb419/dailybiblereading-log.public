import Foundation

public typealias Entry = [String: JSON]

/// A tracker answer scored for the day it describes: a win, a slip, or "didn't happen"
/// (e.g. men's group didn't meet), which counts neither way.
public enum Mark: Equatable, Sendable { case good, bad, off }

/// The whole reading log: the same JSON document the website saves, plus the clock it is read
/// against. Every scoring rule here is a straight port of the matching function in index.html,
/// and the parity tests hold the two to identical answers.
public struct Log: Sendable {
    public var state: JSON
    public var days: Days

    public init(state: JSON = .object([:]), days: Days = Days()) {
        self.state = state
        self.days = days
        normalize()
    }

    /// The website's `load()`: make sure every top-level collection exists.
    public mutating func normalize() {
        if state.object == nil { state = .object([:]) }
        if state["version"] == nil { state["version"] = 1 }
        if state["entries"]?.object == nil { state["entries"] = .object([:]) }
        if state["goals"]?.array == nil { state["goals"] = .array([]) }
        if state["marks"]?.object == nil { state["marks"] = .object([:]) }
        if state["myQuotes"]?.array == nil { state["myQuotes"] = .array([]) }
    }

    var today: DayKey { days.today }

    // MARK: entries

    public var entries: [String: JSON] {
        get { state["entries"]?.object ?? [:] }
        set { state["entries"] = .object(newValue) }
    }
    public func entry(_ day: Int) -> Entry? { entries[String(day)]?.object }
    public mutating func setEntry(_ day: Int, _ e: Entry?) {
        var all = entries
        all[String(day)] = e.map { .object($0) }
        entries = all
    }
    /// Entries in the order the website walks them (integer keys ascend in JS objects).
    public var orderedEntries: [(day: Int, entry: Entry)] {
        entries.compactMap { k, v in Int(k).flatMap { n in v.object.map { (n, $0) } } }.sorted { $0.day < $1.day }
    }
    public var loggedDays: [Int] { orderedEntries.map(\.day) }

    public static func str(_ e: Entry?, _ k: String) -> String { e?[k]?.string ?? "" }
    public static func savedAt(_ e: Entry?) -> String { str(e, "savedAt") }

    public func answered(_ e: Entry?) -> Int {
        guard let e = e else { return 0 }
        return questions.filter { !(e[$0.id]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }
    public func isComplete(_ e: Entry?) -> Bool { e != nil && answered(e) == questions.count }
    /// No reading written but a stored date that isn't today: a leftover whose marks aren't trusted.
    public func isStale(_ e: Entry?) -> Bool {
        guard let e = e else { return false }
        let d = Log.str(e, "date")
        return answered(e) == 0 && !d.isEmpty && d != today
    }
    /// First plan day with no written answers.
    public var nextUnloggedDay: Int {
        for d in 1...ReadingPlan.count where answered(entry(d)) == 0 { return d }
        return ReadingPlan.count
    }
    /// Today's working day: the first that is unwritten or was written today.
    public var currentDay: Int {
        for d in 1...ReadingPlan.count {
            let e = entry(d)
            if e == nil || answered(e) == 0 || Log.str(e, "date") == today { return d }
        }
        return ReadingPlan.count
    }

    // MARK: scoring by calendar date

    /// Calendar date → the entry shown for it (the most-answered one).
    public var dateMap: [DayKey: (day: Int, entry: Entry)] {
        var m: [DayKey: (day: Int, entry: Entry)] = [:]
        for (n, e) in orderedEntries {
            let d = Log.str(e, "date")
            guard !d.isEmpty else { continue }
            if let cur = m[d], answered(e) <= answered(cur.entry) { continue }
            m[d] = (n, e)
        }
        return m
    }
    /// Calendar date → plan day number, ignoring stale entries.
    public var planDayMap: [DayKey: Int] {
        var best: [DayKey: Entry] = [:], out: [DayKey: Int] = [:]
        for (n, e) in orderedEntries {
            let d = Log.str(e, "date")
            guard !d.isEmpty, !isStale(e) else { continue }
            if let cur = best[d], answered(e) <= answered(cur) { continue }
            best[d] = e; out[d] = n
        }
        return out
    }
    public var firstDate: DayKey? { dateMap.keys.min() }

    public enum DayState: String, Sendable { case complete, partial, missed, fail }

    public struct MonthStats: Sendable, Equatable {
        public let y: Int, m: Int, first: Int, last: Int, elapsed: Int, complete: Int, partial: Int
        public let marks: [Int: DayState]
        public let pct: Double
    }
    public func monthStats(_ y: Int, _ m: Int) -> MonthStats? {
        guard let start = firstDate else { return nil }
        let dm = dateMap, s = Days.parts(start), now = Days.parts(today)
        let first = (y == s.y && m == s.m) ? s.d : 1
        let last = (y == now.y && m == now.m) ? now.d : days.daysInMonth(y, m)
        var complete = 0, partial = 0, marks: [Int: DayState] = [:]
        if first <= last {
            for d in first...last {
                let e = dm[Days.make(y, m, d)]?.entry
                if isComplete(e) { complete += 1; marks[d] = .complete }
                else if e != nil && answered(e) > 0 { partial += 1; marks[d] = .partial }
                else { marks[d] = .missed }
            }
        }
        let elapsed = last - first + 1
        return MonthStats(y: y, m: m, first: first, last: last, elapsed: elapsed, complete: complete, partial: partial,
                          marks: marks, pct: elapsed > 0 ? Double(complete) / Double(elapsed) * 100 : 0)
    }
    /// Every month from the first entry to now, newest first.
    public var allMonths: [MonthStats] {
        guard let start = firstDate else { return [] }
        let s = Days.parts(start), now = Days.parts(today)
        var out: [MonthStats] = [], y = s.y, m = s.m
        while y < now.y || (y == now.y && m <= now.m) {
            if let st = monthStats(y, m) { out.append(st) }
            m += 1; if m > 12 { m = 1; y += 1 }
        }
        return out.reversed()
    }

    public struct WeekDay: Sendable, Equatable { public let k: DayKey; public let state: DayState }
    public struct WeekStats: Sendable, Equatable {
        public let days: [WeekDay]
        public let complete: Int, elapsed: Int
        public let pct: Double
    }
    public var weekStats: WeekStats? {
        guard let start = firstDate else { return nil }
        let dm = dateMap
        var out: [WeekDay] = []
        for i in stride(from: 6, through: 0, by: -1) {
            let k = days.shift(today, -i)
            if k < start { continue }
            let e = dm[k]?.entry
            out.append(.init(k: k, state: isComplete(e) ? .complete : (e != nil && answered(e) > 0 ? .partial : .missed)))
        }
        let c = out.filter { $0.state == .complete }.count
        return .init(days: out, complete: c, elapsed: out.count, pct: out.isEmpty ? 0 : Double(c) / Double(out.count) * 100)
    }

    // MARK: trackers, scored by the day each answer describes

    public static func hasVal(_ f: String, _ x: JSON?) -> Bool {
        if numericFields[f] != nil { if let n = x?.number { return n.isFinite }; return false }
        guard let s = x?.string else { return false }
        return s == "yes" || s == "no" || s == "off"
    }

    public func trackerMap(_ f: String) -> [DayKey: Mark] {
        guard let t = tracker(f) else { return [:] }
        func score(_ x: JSON?) -> Mark { x?.string == "off" ? .off : (x?.string == t.good ? .good : .bad) }
        var m: [DayKey: (Mark, String)] = [:]
        for (_, e) in orderedEntries {
            let d = Log.str(e, "date")
            guard !d.isEmpty, Log.hasVal(f, e[f]) else { continue }
            let key = days.shift(d, t.shift), at = Log.savedAt(e)
            if let cur = m[key], !(at > cur.1) { continue }
            m[key] = (score(e[f]), at)
        }
        for (dk, r) in marks {
            let at = r[f + "At"]?.string ?? ""
            guard Log.hasVal(f, r[f]) else { continue }
            if let cur = m[dk], !(at > cur.1) { continue }
            m[dk] = (score(r[f]), at)
        }
        return m.mapValues(\.0)
    }
    public static func first(_ map: [DayKey: Mark]) -> DayKey? { map.keys.min() }
    /// The latest day a tracker can be answered for: yesterday for P/M/MG, today for the rest.
    public func trackerNow(_ f: String) -> DayKey { (tracker(f)?.shift ?? 0) < 0 ? days.yesterday : today }

    public struct TrackerStats: Sendable, Equatable { public let clean: Int, elapsed: Int; public let pct: Double }
    public func trackerMonth(_ map: [DayKey: Mark], first: DayKey, _ y: Int, _ m: Int, now nowKey: DayKey? = nil, weekday wd: Int? = nil) -> TrackerStats? {
        let s = Days.parts(first), now = Days.parts(nowKey ?? days.yesterday)
        if y > now.y || (y == now.y && m > now.m) { return nil }
        if y < s.y || (y == s.y && m < s.m) { return nil }
        let a = (y == s.y && m == s.m) ? s.d : 1
        let b = (y == now.y && m == now.m) ? now.d : days.daysInMonth(y, m)
        if b < a { return nil }
        var clean = 0, el = 0
        for d in a...b {
            let k = Days.make(y, m, d)
            if let wd = wd, days.weekday(k) != wd { continue }
            if map[k] == .off { continue }
            el += 1
            if map[k] == .good { clean += 1 }
        }
        if el == 0 { return nil }
        return .init(clean: clean, elapsed: el, pct: Double(clean) / Double(el) * 100)
    }

    public struct TrackerWeek: Sendable, Equatable { public let days: [WeekDay]; public let n: Int, elapsed: Int; public let pct: Double }
    public func trackerWeek(_ map: [DayKey: Mark], first: DayKey, now nowKey: DayKey? = nil, weekday wd: Int? = nil) -> TrackerWeek {
        let nowK = nowKey ?? days.yesterday
        var out: [WeekDay] = [], n = 0
        for i in stride(from: 6, through: 0, by: -1) {
            let k = days.shift(nowK, -i)
            if k < first { continue }
            if let wd = wd, days.weekday(k) != wd { continue }
            let v = map[k]
            if v == .off { continue }
            out.append(.init(k: k, state: v == .good ? .complete : (v == .bad ? .fail : .missed)))
            if v == .good { n += 1 }
        }
        return .init(days: out, n: n, elapsed: out.count, pct: out.isEmpty ? 0 : Double(n) / Double(out.count) * 100)
    }

    // MARK: calendar backfill marks
    // state.marks[day] = {p:"yes"|"no"|"", pAt:iso, …}, keyed to the day the answer describes.

    public var marks: [DayKey: [String: JSON]] {
        (state["marks"]?.object ?? [:]).compactMapValues(\.object)
    }
    public func markVal(_ f: String, _ dk: DayKey) -> JSON? {
        let v = state["marks"]?[dk]?[f]
        return Log.hasVal(f, v) ? v : nil
    }
    mutating func putMark(_ f: String, _ dk: DayKey, _ v: JSON?) {
        var all = state["marks"]?.object ?? [:]
        var r = all[dk]?.object ?? [:]
        let empty = v == nil || v == .null || v?.string == ""
        r[f] = empty ? "" : v!
        r[f + "At"] = .string(days.stamp())
        all[dk] = .object(r)
        state["marks"] = .object(all)
    }
    /// Per day and field, the most recent edit wins.
    @discardableResult
    public mutating func mergeMarks(_ src: JSON?) -> Bool {
        var changed = false
        var all = state["marks"]?.object ?? [:]
        let fields = trackers.map(\.id) + numericFields.keys.sorted()
        for (dk, theirsJ) in src?.object ?? [:] {
            let theirs = theirsJ.object ?? [:]
            var mine = all[dk]?.object ?? [:]
            for f in fields {
                let at = f + "At"
                if let t = theirs[at], t.truthy, (t.string ?? "") > (mine[at]?.string ?? "") {
                    let v = theirs[f]
                    mine[f] = (v == nil || v == .null) ? "" : v!
                    mine[at] = t
                    changed = true
                }
            }
            if !mine.isEmpty { all[dk] = .object(mine) }
        }
        state["marks"] = .object(all)
        return changed
    }
    /// Set (or clear, with "" / nil) field f for day dk from the calendar. If a written entry
    /// already holds that answer, or is the entry whose Today card asks it, that entry is edited
    /// so the Today card and the calendar never disagree; otherwise a mark is stored.
    public mutating func setMark(_ f: String, _ dk: DayKey, _ v: JSON?) {
        let shift = numericFields[f] ?? tracker(f)?.shift ?? 0
        let sd = days.shift(dk, -shift), cur = currentDay
        var holder: (Int, Entry)? = nil, host: (Int, Entry)? = nil
        for (n, e) in orderedEntries {
            if Log.str(e, "date") != sd || isStale(e) { continue }
            if Log.hasVal(f, e[f]) && (holder == nil || Log.savedAt(e) > Log.savedAt(holder!.1)) { holder = (n, e) }
            if host == nil && (sd < today || n == cur) { host = (n, e) }
        }
        if let (n, found) = holder ?? host {
            var e = found
            let empty = v == nil || v == .null || v?.string == ""
            if empty { e[f] = nil } else { e[f] = v! }
            e["savedAt"] = .string(days.stamp())
            setEntry(n, e)
            if markVal(f, dk) != nil { putMark(f, dk, "") }
        } else {
            putMark(f, dk, v)
        }
    }
}
