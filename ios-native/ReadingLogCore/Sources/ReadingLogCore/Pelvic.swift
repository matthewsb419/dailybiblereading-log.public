import Foundation

// Pelvic floor: a guided session, several a day, with progressive overload and a deload every
// fourth week. A week only moves you up a level if at least half its sessions were done.

public struct KegWeek: Sendable, Equatable {
    public let start: DayKey, lvl: Int, done: Int, target: Int, closed: Bool
}
public struct KegProgram: Sendable {
    public let level: Int
    public let weeks: [KegWeek]
    public let plan: KegLevel
    public let week: KegWeek?
    public let next: KegLevel
}
public struct KegDay: Sendable, Equatable { public let k: DayKey; public let n: Int; public let g: Int }
public struct KegGrade: Sendable, Equatable {
    public let pct: Double, grade: String, full: Int, pass: Int, miss: Int, n: Int
}
public struct KegStats: Sendable {
    public let prog: KegProgram
    public var plan: KegLevel { prog.plan }
    public var goal: Int { prog.plan.sets }
    public let today: Int, total: Int, days: Int, atGoal: Int, anyDay: Int, streak: Int
    public let last7: [KegDay], avg: Double, all: [KegDay], closed: [KegDay], wk7: [KegDay]
    public let wkGrade: KegGrade?, allGrade: KegGrade?
}
public struct KegStep: Sendable, Equatable {
    public enum Kind: String, Sendable { case ready, hold, rest, `break`, flick, frest }
    public let k: Kind, label: String, sub: String, secs: Int
}

extension Log {
    public static func kegLevelPlan(_ level: Int) -> KegLevel {
        let l = max(1, level)
        if l <= kegLevels.count { return kegLevels[l - 1] }
        // past the twelfth week it holds at the top, still deloading every fourth week
        return (l - (kegLevels.count + 1)) % 4 == 3
            ? KegLevel(hold: 7, reps: 8, flicks: 10, sets: 2, name: "Deload")
            : KegLevel(hold: 10, reps: 12, flicks: 15, sets: 3, name: "Maintain")
    }

    /// Day → sessions done; the most recent edit wins.
    public var kegMap: [DayKey: Int] {
        var m: [DayKey: (Int, String)] = [:]
        for (_, e) in orderedEntries {
            let d = Log.str(e, "date")
            guard !d.isEmpty, !isStale(e), Log.hasVal("kg", e["kg"]), let v = e["kg"]?.number else { continue }
            let at = Log.savedAt(e)
            if let cur = m[d], !(at > cur.1) { continue }
            m[d] = (Int(v), at)
        }
        for (dk, r) in marks {
            let at = r["kgAt"]?.string ?? ""
            guard Log.hasVal("kg", r["kg"]), let v = r["kg"]?.number else { continue }
            if let cur = m[dk], !(at > cur.1) { continue }
            m[dk] = (Int(v), at)
        }
        return m.mapValues(\.0)
    }

    public var kegProgram: KegProgram {
        let m = kegMap
        var lvl = 1, weeks: [KegWeek] = [], d = Program.kegStart
        while d <= today {
            let sets = Log.kegLevelPlan(lvl).sets
            var done = 0, target = 0, closed = true
            for i in 0..<7 {
                let k = days.shift(d, i)
                if k > today { closed = false } else { done += m[k] ?? 0; target += sets }
            }
            weeks.append(.init(start: d, lvl: lvl, done: done, target: target, closed: closed))
            if closed && target > 0 && Double(done) >= Double(target) / 2 { lvl += 1 }
            d = days.shift(d, 7)
        }
        return .init(level: lvl, weeks: weeks, plan: Log.kegLevelPlan(lvl), week: weeks.last, next: Log.kegLevelPlan(lvl + 1))
    }
    /// The daily session goal for the week that day fell in.
    public static func kegGoal(_ prog: KegProgram, _ k: DayKey) -> Int {
        for w in prog.weeks.reversed() where k >= w.start { return kegLevelPlan(w.lvl).sets }
        return prog.plan.sets
    }
    /// All of the day's sessions is full marks; one short of it is a pass, not a miss.
    public static func kegDayPct(_ n: Int, _ g: Int) -> Double {
        if g <= 0 || n >= g { return 100 }
        if g > 1 && n >= g - 1 { return 80 }
        return Double(n) / Double(g) * 100
    }
    /// A+ only when every day hit the full count.
    public static func kegGrade(_ list: [KegDay]) -> KegGrade? {
        guard !list.isEmpty else { return nil }
        var sum = 0.0, full = 0, pass = 0, miss = 0
        for d in list {
            sum += kegDayPct(d.n, d.g)
            if d.n >= d.g { full += 1 } else if d.g > 1 && d.n >= d.g - 1 { pass += 1 } else { miss += 1 }
        }
        let pct = sum / Double(list.count), allFull = full == list.count
        var g = allFull ? "A+" : Program.grade(pct)
        if !allFull && g == "A+" { g = "A" }
        return .init(pct: pct, grade: g, full: full, pass: pass, miss: miss, n: list.count)
    }

    public var kegStats: KegStats {
        let m = kegMap, prog = kegProgram
        var total = 0, atGoal = 0, anyDay = 0, count = 0, all: [KegDay] = []
        for k in days.range(Program.kegStart, today) {
            let n = m[k] ?? 0, g = Log.kegGoal(prog, k)
            count += 1; total += n
            all.append(.init(k: k, n: n, g: g))
            if n >= g { atGoal += 1 }
            if n > 0 { anyDay += 1 }
        }
        // today stays open until it reaches the full count, so it can't drag a grade down
        var closed = all
        if let l = closed.last, l.k == today, l.n < l.g { closed.removeLast() }
        let wk7 = Array(closed.suffix(7))
        var streak = 0, w = today
        if (m[today] ?? 0) < Log.kegGoal(prog, today) { w = days.shift(w, -1) }
        while w >= Program.kegStart && (m[w] ?? 0) >= Log.kegGoal(prog, w) { streak += 1; w = days.shift(w, -1) }
        var last7: [KegDay] = []
        for i in stride(from: 6, through: 0, by: -1) {
            let k = days.shift(today, -i)
            if k >= Program.kegStart { last7.append(.init(k: k, n: m[k] ?? 0, g: Log.kegGoal(prog, k))) }
        }
        return KegStats(prog: prog, today: m[today] ?? 0, total: total, days: count, atGoal: atGoal, anyDay: anyDay, streak: streak,
                        last7: last7, avg: count > 0 ? Double(total) / Double(count) : 0, all: all, closed: closed, wk7: wk7,
                        wkGrade: Log.kegGrade(wk7), allGrade: Log.kegGrade(closed))
    }

    /// The timed steps of one session at this week's level.
    public var kegSteps: [KegStep] {
        let p = kegProgram.plan
        var out = [KegStep(k: .ready, label: "Get ready", sub: "Breathe normally — don’t clench your stomach, thighs or buttocks", secs: 5)]
        for i in 1...p.reps {
            out.append(.init(k: .hold, label: "Squeeze", sub: "Lift and hold · \(i) of \(p.reps)", secs: p.hold))
            out.append(.init(k: .rest, label: "Relax", sub: "Let go completely · \(i) of \(p.reps)", secs: p.hold))
        }
        out.append(.init(k: .break, label: "Break", sub: "Quick flicks next", secs: Program.kegBreak))
        for j in 1...p.flicks {
            out.append(.init(k: .flick, label: "Quick squeeze", sub: "Flick \(j) of \(p.flicks)", secs: Program.kegFlickHold))
            out.append(.init(k: .frest, label: "Let go", sub: "Flick \(j) of \(p.flicks)", secs: Program.kegFlickRest))
        }
        return out
    }

    public static func parseKeg(_ s: String) -> Int? {
        let d = s.filter(\.isASCII).filter(\.isNumber)
        guard !d.isEmpty, let n = Int(d.prefix(9)) else { return nil }
        return min(n, 20)
    }

    /// One more finished session today.
    public mutating func kegAdd(_ n: Int = 1) {
        setMark("kg", today, .number(Double((kegMap[today] ?? 0) + n)))
    }
}
