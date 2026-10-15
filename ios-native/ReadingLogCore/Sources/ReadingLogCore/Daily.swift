import Foundation

// MARK: daily habits — one score across everything being tracked
// Every habit carries the same weight: each is scored over its own applicable days, then the
// percentages are averaged flat. Today is left out until it closes.

public struct HabitDef: Sendable {
    public let id: String, label: String, from: DayKey
    public var to: DayKey? = nil
    public var weekday: Int? = nil
    /// 0–100, or nil when the habit didn't apply that day
    public let score: @Sendable (DayKey) -> Double?
}
public struct HabitScore: Sendable, Equatable { public let id: String, label: String; public let pct: Double; public let n: Int }
public struct HabitWindow: Sendable, Equatable { public let per: [HabitScore]; public let pct: Double; public let n: Int }

extension Log {
    public var habitDefs: [HabitDef] {
        let prog = kegProgram, dm = dateMap, sMap = stepMap, kMap = kegMap
        let pace = Program.stepGoal / Double(days.count(Program.stepStart, Program.stepEnd))
        var defs: [HabitDef] = []
        let me = self
        if let rf = firstDate {
            defs.append(.init(id: "read", label: "Reading", from: rf, score: { k in
                guard let e = dm[k]?.entry else { return 0 }
                return Double(me.answered(e)) / 3 * 100
            }))
        }
        for t in trackers {
            let map = trackerMap(t.id)
            guard let from = t.start ?? Log.first(map) else { continue }
            defs.append(.init(id: t.id, label: t.label, from: from, weekday: t.weekday, score: { k in
                switch map[k] { case .off: return nil; case .good: return 100; default: return 0 }
            }))
        }
        if today > Program.stepStart {
            defs.append(.init(id: "st", label: "Steps", from: Program.stepStart, to: Program.stepEnd, score: { k in
                guard let v = sMap[k] else { return 0 }
                return min(100, v / pace * 100)
            }))
        }
        if today >= Program.kegStart {
            defs.append(.init(id: "kg", label: "Sessions", from: Program.kegStart, score: { k in
                Log.kegDayPct(kMap[k] ?? 0, Log.kegGoal(prog, k))
            }))
        }
        return defs
    }

    public func habitWindow(_ defs: [HabitDef], from fromK: DayKey, to toK: DayKey) -> HabitWindow {
        var per: [HabitScore] = [], sum = 0.0
        for d in defs {
            let startK = fromK > d.from ? fromK : d.from
            if startK > toK { continue }
            var tot = 0.0, n = 0
            for k in days.range(startK, toK) {
                if let to = d.to, k > to { break }
                if let wd = d.weekday, days.weekday(k) != wd { continue }
                guard let v = d.score(k) else { continue }
                tot += v; n += 1
            }
            if n > 0 { let pct = tot / Double(n); per.append(.init(id: d.id, label: d.label, pct: pct, n: n)); sum += pct }
        }
        return .init(per: per, pct: per.isEmpty ? 0 : sum / Double(per.count), n: per.count)
    }
}

// MARK: extra credit — 1 Timothy, one chapter a day
// The chapter cycles 1…6 from Sep 6 to Christmas Eve; the question is keyed to the chapter's
// pass number, so nothing repeats until the bank runs out.

public struct ExtraCredit: Sendable, Equatable {
    public let ch: Int, qi: Int, q: String, ref: String
    public let n: Int?, cycle: Int?, week: Int?, pass: Int?
}

extension Log {
    func ecOffset(_ k: DayKey) -> Int { days.between(Program.ecStart, k) }
    static func ecBank(_ ch: Int) -> [String] {
        let all = Content.shared.extraCredit
        return ch >= 1 && ch <= all.count ? all[ch - 1] : []
    }
    /// What the extra credit is on a calendar date, or nil outside the run.
    public func ecFor(_ k: DayKey?) -> ExtraCredit? {
        guard let k = k, !k.isEmpty, k >= Program.ecStart, k <= Program.ecEnd else { return nil }
        let n = ecOffset(k)
        if n < 0 { return nil }
        let ch = n % Program.ecCycle + 1, cycle = n / Program.ecCycle, bank = Log.ecBank(ch)
        if bank.isEmpty { return nil }
        let qi = cycle % bank.count
        return .init(ch: ch, qi: qi, q: bank[qi], ref: "1 Timothy \(ch)", n: n, cycle: cycle, week: n / 7 + 1, pass: cycle + 1)
    }
    /// An answer already written keeps its own chapter and question, whatever the date says now.
    public func ecStored(_ e: Entry?) -> ExtraCredit? {
        guard let e = e, !Log.str(e, "ec").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let chJ = e["ecCh"], chJ.truthy else { return nil }
        let ch = Int(chJ.number ?? Double(chJ.string ?? "") ?? 0), qi = Int(e["ecQ"]?.number ?? 0), bank = Log.ecBank(ch)
        return .init(ch: ch, qi: qi, q: qi < bank.count && qi >= 0 ? bank[qi] : "", ref: "1 Timothy \(ch)", n: nil, cycle: nil, week: nil, pass: nil)
    }
    /// Calendar days in the run so far (capped at Christmas Eve).
    public var ecDays: Int {
        let last = today < Program.ecEnd ? today : Program.ecEnd
        return last < Program.ecStart ? 0 : ecOffset(last) + 1
    }
    public var ecTotalDays: Int { ecOffset(Program.ecEnd) + 1 }
    /// Date → the entry holding that day's extra credit.
    public var ecMap: [DayKey: Entry] {
        var m: [DayKey: Entry] = [:]
        for (_, e) in orderedEntries {
            let d = Log.str(e, "date")
            guard !d.isEmpty, !Log.str(e, "ec").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            if let cur = m[d], !(Log.savedAt(e) > Log.savedAt(cur)) { continue }
            m[d] = e
        }
        return m
    }
}

// MARK: life goals and quotes

extension Log {
    public var goals: [String] { state["goals"]?.array?.compactMap(\.string) ?? [] }

    static func djb2(_ s: String) -> UInt32 {
        var x: UInt32 = 5381
        for c in s.utf16 { x = (x << 5) &+ x &+ UInt32(c) }
        return x
    }
    /// One goal per date, seeded from the date so every device agrees; never the same two days running.
    public func goalIndex(_ k: DayKey, _ n: Int) -> Int {
        if n <= 0 { return -1 }
        var i = Int(Log.djb2(k) % UInt32(n))
        if n > 1 && i == Int(Log.djb2(days.shift(k, -1)) % UInt32(n)) { i = (i + 1) % n }
        return i
    }

    /// The user's own quotes, oldest first; deleted ones stay in the data as tombstones.
    public var myQuotes: [Quote] {
        let raw = (state["myQuotes"]?.array ?? []).compactMap(\.object).filter {
            !($0["del"]?.truthy ?? false) && !(($0["t"]?.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        let sorted = raw.sorted { x, y in
            let mx = x["made"]?.string ?? "", my = y["made"]?.string ?? ""
            if mx != my { return mx < my }
            return (x["id"]?.string ?? "") < (y["id"]?.string ?? "")
        }
        return sorted.map { Quote(c: "mine", a: $0["a"]?.string ?? "", t: $0["t"]?.string ?? "", id: $0["id"]?.string) }
    }
    /// Built-ins first, then the user's own, in the same order on every device.
    public var quoteBank: [Quote] { Content.shared.quotes + myQuotes }

    /// Walks a shuffled deck of every quote, reshuffled each pass and seeded from the date, so
    /// nothing repeats until the whole list has been seen and both devices agree all day.
    public func quoteIndex(_ k: DayKey) -> Int {
        let n = quoteBank.count
        guard n > 0 else { return 0 }
        let p = Days.parts(k)
        let day = Log.daysFromCivil(p.y, p.m, p.d)
        func deck(_ cyc: Int) -> [Int] {
            var s = UInt32(truncatingIfNeeded: Int64(cyc) &* 2_654_435_761 &+ 97)
            func rnd() -> Double {
                s = s &+ 0x6D2B79F5
                var t = s
                t = (t ^ (t >> 15)) &* (t | 1)
                t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
                return Double(t ^ (t >> 14)) / 4_294_967_296
            }
            var a = Array(0..<n)
            var j = n - 1
            while j > 0 { let r = Int((rnd() * Double(j + 1)).rounded(.down)); a.swapAt(j, r); j -= 1 }
            return a
        }
        let cyc = Int((Double(day) / Double(n)).rounded(.down)), pos = day - cyc * n
        var d = deck(cyc)
        if n > 1 && d[0] == deck(cyc - 1)[n - 1] { d.swapAt(0, 1) }
        return d[pos]
    }
    /// Days since 1970-01-01 for a calendar date (`Date.UTC(y, m-1, d) / 86400000`).
    static func daysFromCivil(_ y0: Int, _ m: Int, _ d: Int) -> Int {
        let y = m <= 2 ? y0 - 1 : y0
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    public mutating func saveGoals(_ text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map { line -> String in
            var s = String(line)
            if let r = s.range(of: #"^\s*\d+[.)]\s*"#, options: .regularExpression) { s.removeSubrange(r) }
            return s.trimmingCharacters(in: .whitespaces)
        }.filter { !$0.isEmpty }
        state["goals"] = .array(lines.map { .string($0) })
        state["goalsSavedAt"] = .string(days.stamp())
    }

    /// Add a quote, or change one (by id).
    public mutating func saveQuote(id: String?, text: String, by: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines), a = by.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        var list = state["myQuotes"]?.array ?? []
        let now = days.stamp()
        if let id = id, let i = list.firstIndex(where: { $0["id"]?.string == id && !($0["del"]?.truthy ?? false) }) {
            list[i]["t"] = .string(t); list[i]["a"] = .string(a); list[i]["at"] = .string(now)
        } else {
            let newID = String(Int(days.now.timeIntervalSince1970 * 1000), radix: 36) + String(UUID().uuidString.lowercased().prefix(4))
            list.append(["id": .string(newID), "t": .string(t), "a": .string(a), "made": .string(now), "at": .string(now)])
        }
        state["myQuotes"] = .array(list)
    }
    /// Deleting leaves a tombstone so the delete syncs.
    public mutating func deleteQuote(id: String) {
        var list = state["myQuotes"]?.array ?? []
        for i in list.indices where list[i]["id"]?.string == id {
            list[i]["del"] = true; list[i]["t"] = ""; list[i]["a"] = ""; list[i]["at"] = .string(days.stamp())
        }
        state["myQuotes"] = .array(list)
    }
}
