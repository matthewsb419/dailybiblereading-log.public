import Foundation
import XCTest
@testable import ReadingLogCore

/// Holds the Swift port to the website's own answers. Fixtures/fixtures.json is produced by
/// tools/make-fixtures.mjs, which runs index.html's real code on a made-up log for several dates.
final class ParityTests: XCTestCase {
    static let fixtures: JSON = {
        let url = Bundle.module.url(forResource: "fixtures", withExtension: "json", subdirectory: "Fixtures")!
        return try! JSON.parse(Data(contentsOf: url))
    }()
    var fx: JSON { Self.fixtures }
    var zone: TimeZone { TimeZone(identifier: fx["timeZone"]?.string ?? "UTC")! }

    func log(at now: String, state: JSON? = nil) -> Log {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return Log(state: state ?? fx["state"]!, days: Days(now: f.date(from: now)!, timeZone: zone))
    }

    // MARK: comparing

    /// Expected (from JS) against actual (from Swift): numbers within rounding noise, and a
    /// missing key the same as null, since JSON.stringify drops `undefined`.
    func same(_ a: JSON?, _ b: JSON?, _ path: String, _ fails: inout [String]) {
        let x = a ?? .null, y = b ?? .null
        switch (x, y) {
        case (.number(let p), .number(let q)):
            if abs(p - q) > 1e-6 * max(1, abs(p)) { fails.append("\(path): web \(p) swift \(q)") }
        case (.object(let p), .object(let q)):
            for k in Set(p.keys).union(q.keys) { same(p[k], q[k], path + "." + k, &fails) }
        case (.array(let p), .array(let q)):
            if p.count != q.count { fails.append("\(path): web \(p.count) items, swift \(q.count)"); return }
            for i in p.indices { same(p[i], q[i], "\(path)[\(i)]", &fails) }
        default:
            if x != y { fails.append("\(path): web \(x.text()) swift \(y.text())") }
        }
    }
    func check(_ web: JSON?, _ swift: JSON, _ path: String, file: StaticString = #filePath, line: UInt = #line) {
        var fails: [String] = []
        same(web, swift, path, &fails)
        XCTAssert(fails.isEmpty, "\(fails.count) differences:\n" + fails.prefix(15).joined(separator: "\n"), file: file, line: line)
    }

    // MARK: Swift values as JSON

    func j(_ s: String?) -> JSON { s.map { .string($0) } ?? .null }
    func j(_ n: Double?) -> JSON { n.map { .number($0) } ?? .null }
    func j(_ n: Int?) -> JSON { n.map { .number(Double($0)) } ?? .null }
    func j(_ m: Mark?) -> JSON { switch m { case .good: return true; case .bad: return false; default: return .null } }
    func j(_ w: Log.WeekDay) -> JSON { ["k": j(w.k), "state": j(w.state.rawValue)] }
    func j(_ l: KegLevel) -> JSON { ["hold": j(l.hold), "reps": j(l.reps), "flicks": j(l.flicks), "sets": j(l.sets), "name": j(l.name)] }
    func j(_ g: KegGrade?) -> JSON {
        guard let g = g else { return .null }
        return ["pct": j(g.pct), "grade": j(g.grade), "full": j(g.full), "pass": j(g.pass), "miss": j(g.miss), "n": j(g.n)]
    }
    func j(_ d: KegDay) -> JSON { ["k": j(d.k), "n": j(d.n), "g": j(d.g)] }
    func j(_ h: HabitWindow) -> JSON {
        ["per": .array(h.per.map { ["id": j($0.id), "label": j($0.label), "pct": j($0.pct), "n": j($0.n)] }), "pct": j(h.pct), "n": j(h.n)]
    }
    func j(_ m: Log.MonthStats?) -> JSON {
        guard let m = m else { return .null }
        return ["y": j(m.y), "m": j(m.m), "first": j(m.first), "last": j(m.last), "elapsed": j(m.elapsed),
                "complete": j(m.complete), "partial": j(m.partial), "pct": j(m.pct),
                "marks": .object(Dictionary(uniqueKeysWithValues: m.marks.map { (String($0.key), j($0.value.rawValue)) }))]
    }
    func j(_ t: Log.TrackerStats?) -> JSON {
        guard let t = t else { return .null }
        return ["clean": j(t.clean), "elapsed": j(t.elapsed), "pct": j(t.pct)]
    }
    func j(_ x: ExtraCredit?) -> JSON {
        guard let x = x else { return .null }
        return ["n": j(x.n), "ch": j(x.ch), "cycle": j(x.cycle), "qi": j(x.qi), "q": j(x.q), "ref": j(x.ref), "week": j(x.week), "pass": j(x.pass)]
    }

    // MARK: tests

    func testPlan() {
        let web = fx["plan"]!.array!
        XCTAssertEqual(web.count, ReadingPlan.count)
        check(.array(web), .array(ReadingPlan.days.map {
            ["book": j($0.book), "read": j($0.read), "verses": j($0.verses), "min": j($0.min), "day": j($0.day)]
        }), "plan")
    }

    func testSnapshots() {
        for snap in fx["snapshots"]!.array! {
            let now = snap["now"]!.string!
            let lg = log(at: now)
            let p = "[\(now)]"
            XCTAssertEqual(lg.days.today, snap["today"]?.string, p)
            check(snap["currentDay"], j(lg.currentDay), p + "currentDay")
            check(snap["nextUnloggedDay"], j(lg.nextUnloggedDay), p + "nextUnloggedDay")
            check(snap["dateMapDays"], .object(lg.dateMap.mapValues { j($0.day) }), p + "dateMap")
            check(snap["planDayMap"], .object(lg.planDayMap.mapValues { j($0) }), p + "planDayMap")
            check(snap["firstDate"], j(lg.firstDate), p + "firstDate")
            check(snap["months"], .array(lg.allMonths.map { j($0) }), p + "months")
            let wk = lg.weekStats
            check(snap["week"], wk.map { ["days": .array($0.days.map(j)), "complete": j($0.complete), "elapsed": j($0.elapsed), "pct": j($0.pct)] } ?? .null, p + "week")

            for t in trackers {
                let map = lg.trackerMap(t.id), first = Log.first(map), nowKey = lg.trackerNow(t.id)
                let exp = snap["tracker"]![t.id]!
                check(exp["map"], .object(map.mapValues { j($0) }), p + "tracker.\(t.id).map")
                check(exp["first"], j(first), p + "tracker.\(t.id).first")
                if let first = first {
                    let w = lg.trackerWeek(map, first: first, now: nowKey, weekday: t.weekday)
                    check(exp["week"], ["days": .array(w.days.map(j)), "n": j(w.n), "elapsed": j(w.elapsed), "pct": j(w.pct)], p + "tracker.\(t.id).week")
                    check(exp["months"], .array(lg.allMonths.map { m in
                        ["y": j(m.y), "m": j(m.m), "s": j(lg.trackerMonth(map, first: first, m.y, m.m, now: nowKey, weekday: t.weekday))]
                    }), p + "tracker.\(t.id).months")
                }
            }

            let s = lg.stepStats
            let need = lg.needSeries(s).map { n -> JSON in
                var o: JSON = ["k": j(n.k), "left": j(n.left), "v": j(n.v), "g": j(n.g), "s": j(n.s)]
                if n.start { o["start"] = true } else { o["cum"] = j(n.cum) }
                return o
            }
            check(snap["steps"], [
                "map": .object(s.map.mapValues { j($0) }), "total": j(s.total), "logged": j(s.logged), "best": j(s.best), "bestK": j(s.bestK),
                "pace": j(s.pace), "overPace": j(s.overPace), "streak": j(s.streak), "counted": j(s.counted), "from": j(s.from),
                "daysLeft": j(s.daysLeft), "target": j(s.target), "need": j(s.need), "avg": j(s.avg), "projected": j(s.projected),
                "hitDate": j(s.hitDate), "span": j(s.span), "last": j(s.last), "required": j(s.required), "taken": j(s.taken),
                "pct": j(s.pct), "pass": .bool(s.pass), "grade": j(s.grade), "needText": j(lg.stepNeedText(s)), "needSeries": .array(need)
            ], p + "steps")

            let k = lg.kegStats
            check(snap["keg"], [
                "level": j(k.prog.level),
                "weeks": .array(k.prog.weeks.map { ["start": j($0.start), "lvl": j($0.lvl), "done": j($0.done), "target": j($0.target), "closed": .bool($0.closed)] }),
                "plan": j(k.plan), "next": j(k.prog.next), "today": j(k.today), "total": j(k.total), "days": j(k.days),
                "atGoal": j(k.atGoal), "anyDay": j(k.anyDay), "streak": j(k.streak), "last7": .array(k.last7.map(j)), "avg": j(k.avg),
                "wkGrade": j(k.wkGrade), "allGrade": j(k.allGrade),
                "steps": .array(lg.kegSteps.map { ["k": j($0.k.rawValue), "label": j($0.label), "sub": j($0.sub), "secs": j($0.secs)] })
            ], p + "keg")

            let defs = lg.habitDefs, yest = lg.days.yesterday
            check(snap["habits"], ["week": j(lg.habitWindow(defs, from: lg.days.shift(yest, -6), to: yest)),
                                   "all": j(lg.habitWindow(defs, from: "1900-01-01", to: yest))], p + "habits")

            check(snap["goalIndex"], .object(Dictionary(uniqueKeysWithValues: snap["goalIndex"]!.object!.keys.map { ($0, j(lg.goalIndex($0, lg.goals.count))) })), p + "goalIndex")
            check(snap["quoteIndex"], .object(Dictionary(uniqueKeysWithValues: snap["quoteIndex"]!.object!.keys.map { ($0, j(lg.quoteIndex($0))) })), p + "quoteIndex")
            check(snap["quoteBankSize"], j(lg.quoteBank.count), p + "quoteBankSize")
            check(snap["extraCredit"], .object(Dictionary(uniqueKeysWithValues: snap["extraCredit"]!.object!.keys.map { ($0, j(lg.ecFor($0))) })), p + "extraCredit")
            check(snap["ecDays"], j(lg.ecDays), p + "ecDays")
            check(snap["ecMapDays"], .array(lg.ecMap.keys.sorted().map { j($0) }), p + "ecMapDays")
            XCTAssertEqual(lg.markdown(), snap["markdown"]?.string, p + "markdown")
        }
    }

    func testEdits() {
        for ed in fx["edits"]!.array! {
            let name = ed["name"]!.string!, now = ed["now"]!.string!
            var lg = log(at: now)
            switch name {
            case "mark p yes on a day with an entry": lg.setMark("p", "2026-09-10", "yes")
            case "clear j on a day with an entry": lg.setMark("j", "2026-09-10", "")
            case "mark h on a day with no entry": lg.setMark("h", "2026-08-01", "yes")
            case "steps backfill": lg.setMark("st", "2026-09-30", 12345)
            case "keg add today": lg.kegAdd(1)
            case "merge remote": XCTAssertEqual(lg.mergeRemote(ed["remote"]!), ed["changed"]?.bool)
            default: XCTFail("unknown edit \(name)")
            }
            check(ed["state"], lg.state, "edit[\(name)]")
        }
    }
}
