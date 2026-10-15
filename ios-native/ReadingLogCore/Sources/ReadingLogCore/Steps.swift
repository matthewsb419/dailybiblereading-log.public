import Foundation

// Steps: the walking goal through Valentine's Day. The count on the Today card describes
// YESTERDAY: entry.st, or marks[day].st when filled in from the calendar. Once the main goal is
// reached, the stretch goal takes over everywhere.

public struct StepDay: Sendable, Equatable {
    public let k: DayKey; public let v: Double?
    public init(k: DayKey, v: Double?) { self.k = k; self.v = v }
}

public struct StepStats: Sendable {
    public let map: [DayKey: Double]
    public let days: [StepDay]
    public let total: Double, logged: Int, best: Double, bestK: DayKey?, pace: Double, overPace: Int
    public let streak: Int, counted: Int, from: DayKey, daysLeft: Int, target: Double, need: Double, avg: Double
    public let projected: Double, hitDate: DayKey?, span: Int, last: DayKey
    public let week: [StepDay], required: Double, taken: Double, pct: Double, pass: Bool, grade: String?
}

public struct NeedPoint: Sendable, Equatable {
    public let k: DayKey, start: Bool, left: Int, v: Double?, cum: Double?, g: Double, s: Double
}

extension Log {
    public static func parseSteps(_ s: String) -> Double? {
        let d = s.filter(\.isASCII).filter(\.isNumber)
        guard !d.isEmpty, let n = Double(d) else { return nil }
        return min(n, 250_000)
    }
    public static func stepTarget(_ total: Double) -> Double { total >= Program.stepGoal ? Program.stepStretch : Program.stepGoal }

    /// Day walked → steps; the most recent edit wins.
    public var stepMap: [DayKey: Double] {
        var m: [DayKey: (Double, String)] = [:]
        for (_, e) in orderedEntries {
            let d = Log.str(e, "date")
            guard !d.isEmpty, Log.hasVal("st", e["st"]), let v = e["st"]?.number else { continue }
            let dk = days.shift(d, -1), at = Log.savedAt(e)
            if let cur = m[dk], !(at > cur.1) { continue }
            m[dk] = (v, at)
        }
        for (dk, r) in marks {
            let at = r["stAt"]?.string ?? ""
            guard Log.hasVal("st", r["st"]), let v = r["st"]?.number else { continue }
            if let cur = m[dk], !(at > cur.1) { continue }
            m[dk] = (v, at)
        }
        return m.mapValues(\.0)
    }

    public var stepStats: StepStats {
        let P = Program.self
        let map = stepMap, yk = days.yesterday
        let last = yk < P.stepEnd ? yk : P.stepEnd
        let span = days.count(P.stepStart, P.stepEnd), pace = P.stepGoal / Double(span)
        var list: [StepDay] = [], total = 0.0, logged = 0, best = 0.0, bestK: DayKey? = nil, overPace = 0
        for k in days.range(P.stepStart, last) {
            let v = map[k]
            list.append(.init(k: k, v: v))
            if let v = v { total += v; logged += 1; if v > best { best = v; bestK = k }; if v >= pace { overPace += 1 } }
        }
        // yesterday with no count yet is still open, not a zero
        let closed = (list.last.map { $0.v == nil && $0.k == yk } ?? false) ? Array(list.dropLast()) : list
        var streak = 0
        for x in closed.reversed() { guard let v = x.v, v >= pace else { break }; streak += 1 }
        var from = (map[yk] != nil || yk < P.stepStart) ? today : yk
        if from < P.stepStart { from = P.stepStart }
        let daysLeft = from <= P.stepEnd ? days.count(from, P.stepEnd) : 0
        let target = Log.stepTarget(total), remain = max(0, target - total)
        let need = daysLeft > 0 ? (remain / Double(daysLeft)).rounded(.up) : 0
        let avg = logged > 0 ? total / Double(logged) : 0
        let hitDate = (remain > 0 && avg > 0) ? days.shift(from, Int((remain / avg).rounded(.up)) - 1) : nil
        // trailing 7 days, graded against what the goal needed per day when that stretch began
        let w = Array(closed.suffix(7))
        let before = closed.dropLast(w.count).reduce(0.0) { $0 + ($1.v ?? 0) }
        var taken = 0.0, allOver = !w.isEmpty
        let wNeed = w.isEmpty ? 0 : max(0, Log.stepTarget(before) - before) / Double(days.count(w[0].k, P.stepEnd))
        for x in w { taken += x.v ?? 0; if !((x.v ?? -.infinity) > wNeed) { allOver = false } }
        let required = (wNeed * Double(w.count)).rounded(.up)
        let pct = required > 0 ? taken / required * 100 : 100
        return StepStats(map: map, days: list, total: total, logged: logged, best: best, bestK: bestK, pace: pace, overPace: overPace,
                         streak: streak, counted: closed.count, from: from, daysLeft: daysLeft, target: target, need: need, avg: avg,
                         projected: total + avg * Double(daysLeft), hitDate: hitDate, span: span, last: last,
                         week: w, required: required, taken: taken, pct: pct, pass: !w.isEmpty && pct >= 100,
                         grade: w.isEmpty ? nil : (pct >= 100 ? (allOver ? "A+" : "A") : Program.stepGrade(pct)))
    }

    public func stepNeedText(_ s: StepStats) -> String {
        if s.total >= Program.stepStretch { return "Stretch goal done — \(Fmt.n(s.total)) steps" }
        if s.daysLeft == 0 { return "\(Fmt.n(s.total)) steps — the goal window has closed" }
        return "\(Fmt.n(s.need))/day to reach \(Fmt.n(s.target)) by Feb 14" + (s.total >= Program.stepGoal ? " · goal done, now the stretch" : "")
    }

    /// What every remaining day needs, recomputed after each day's count lands.
    public func needSeries(_ s: StepStats) -> [NeedPoint] {
        let P = Program.self
        let span0 = days.count(P.stepStart, P.stepEnd)
        var out = [NeedPoint(k: P.stepStart, start: true, left: span0, v: nil, cum: nil,
                             g: P.stepGoal / Double(span0), s: P.stepStretch / Double(span0))]
        var run = 0.0
        for d in s.days {
            run += d.v ?? 0
            let after = days.shift(d.k, 1), left = after <= P.stepEnd ? days.count(after, P.stepEnd) : 0
            out.append(.init(k: d.k, start: false, left: left, v: d.v, cum: run,
                             g: left > 0 ? max(0, (P.stepGoal - run) / Double(left)) : 0,
                             s: left > 0 ? max(0, (P.stepStretch - run) / Double(left)) : 0))
        }
        return out
    }
}
