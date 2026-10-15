import SwiftUI
import UIKit
import ReadingLogCore

/// The guided pelvic floor session: steps through the plan with a countdown and a buzz at each
/// change, keeps the screen awake while it runs, and logs a session when it finishes.
@MainActor @Observable
final class KegRunner {
    private(set) var steps: [KegStep] = []
    private(set) var index = 0
    private(set) var left = 0
    private(set) var paused = false
    private(set) var finished = false
    private var endAt = Date()
    private var loop: Task<Void, Never>?
    var running: Bool { !steps.isEmpty && !finished }
    var step: KegStep? { steps.indices.contains(index) ? steps[index] : nil }
    var onFinish: (() -> Void)?

    var progress: Double {
        guard let st = step else { return 0 }
        let tot = steps.reduce(0) { $0 + $1.secs }
        let done = steps.prefix(index).reduce(0) { $0 + $1.secs } + st.secs - left
        return tot > 0 ? min(1, Double(done) / Double(tot)) : 0
    }

    func start(_ plan: [KegStep]) {
        steps = plan; index = 0; paused = false; finished = false
        left = plan.first?.secs ?? 0
        endAt = Date().addingTimeInterval(Double(left))
        UIApplication.shared.isIdleTimerDisabled = true
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                self?.tick()
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }
    func togglePause() {
        guard running else { return }
        paused.toggle()
        if !paused { endAt = Date().addingTimeInterval(Double(left)) }
        UIApplication.shared.isIdleTimerDisabled = !paused
    }
    func quit() { stop(); steps = []; finished = false }
    func reset() { steps = []; finished = false }

    private func tick() {
        guard running, !paused else { return }
        var leftMs = endAt.timeIntervalSinceNow * 1000
        if leftMs <= 0 {
            index += 1
            if index >= steps.count { finish(); return }
            buzz(steps[index].k)
            leftMs = Double(steps[index].secs) * 1000
            endAt = Date().addingTimeInterval(leftMs / 1000)
        }
        let l = max(1, Int((leftMs / 1000).rounded(.up)))
        if l != left { left = l }
    }
    private func finish() {
        stop()
        finished = true
        onFinish?()
        buzz(.hold)
    }
    private func stop() { loop?.cancel(); loop = nil; UIApplication.shared.isIdleTimerDisabled = false }
    private func buzz(_ k: KegStep.Kind) {
        let strong = k == .hold || k == .flick
        UIImpactFeedbackGenerator(style: strong ? .heavy : .light).impactOccurred()
    }
}

/// The session box on the Today card (current day only).
struct KegRow: View {
    @Environment(Store.self) private var store
    @Environment(KegRunner.self) private var keg
    @Environment(\.palette) private var c

    var body: some View {
        let s = store.log.kegStats
        let p = s.plan, goal = s.goal, n = s.today, wk = s.prog.weeks.count
        VStack(alignment: .leading, spacing: 0) {
            if keg.running, let st = keg.step {
                head(st.k == .flick || st.k == .frest ? "Quick flicks" : (st.k == .break ? "Break" : (st.k == .ready ? "Getting ready" : "Endurance holds")))
                let quiet = [.rest, .frest, .break, .ready].contains(st.k)
                Text(st.label).font(.serif(21)).foregroundStyle(quiet ? c.ghost : c.brass).padding(.top, 10)
                Text(keg.paused ? "⏸" : "\(keg.left)").font(.serif(54).monospacedDigit()).foregroundStyle(c.parchment)
                Text(st.sub).font(.system(size: 12)).foregroundStyle(c.muted).padding(.top, 6)
                Meter(pct: keg.progress * 100, marker: nil).padding(.top, 12)
                HStack(spacing: 14) {
                    PillButton(title: keg.paused ? "Resume" : "Pause") { keg.togglePause() }
                    LinkButton(title: "Stop") { keg.quit() }
                }
                .padding(.top, 12)
            } else if keg.finished {
                head("\(n) of \(goal) today")
                Text("Session complete ✓").font(.serif(21)).foregroundStyle(c.brass).padding(.top, 10)
                dots(goal: goal, n: n)
                HStack(spacing: 14) {
                    PillButton(title: n >= goal ? "One more" : "Next session") { begin() }
                    LinkButton(title: "Done for now") { keg.reset() }
                }
                .padding(.top, 12)
            } else {
                head("\(n) of \(goal) today")
                dots(goal: goal, n: n)
                let mins = Int(Fmt.jsRound(Double(store.log.kegSteps.reduce(0) { $0 + $1.secs }) / 60))
                Text("Week \(wk) · \(p.name) · hold \(p.hold)s × \(p.reps), then \(p.flicks) quick flicks · about \(mins) min\n" +
                     (n >= goal ? "All \(goal) done today." : "Session \(n + 1) of \(goal) · \(Program.kegWhere)"))
                    .font(.system(size: 12)).foregroundStyle(c.muted).lineSpacing(2).padding(.top, 6)
                PillButton(title: n > 0 ? "Start next session" : "Start session") { begin() }.padding(.top, 12)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(c.track, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(keg.running || keg.finished ? c.brass : c.line))
    }

    func head(_ right: String) -> some View {
        HStack { Eyebrow(text: "Pelvic floor"); Spacer(); Text(right).font(.system(size: 11)).foregroundStyle(c.muted) }
    }
    func dots(goal: Int, n: Int) -> some View {
        HStack(spacing: 6) {
            ForEach(0..<max(goal, n), id: \.self) { i in
                RoundedRectangle(cornerRadius: 5).fill(i < n ? c.brass : .clear)
                    .overlay(RoundedRectangle(cornerRadius: 5).stroke(i < n ? c.brass : c.line)).frame(width: 22, height: 22)
            }
        }
        .padding(.top, 10)
    }
    func begin() {
        keg.onFinish = { [store] in store.edit { $0.kegAdd(1) } }
        keg.start(store.log.kegSteps)
    }
}

/// The pelvic floor section of the Record page.
struct KegCard: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var c
    @Binding var page: Page

    var body: some View {
        let s = store.log.kegStats, p = s.plan, nx = s.prog.next, lg = store.log
        let wk = s.prog.week, pct = s.days > 0 ? Double(s.atGoal) / Double(s.days) * 100 : 0
        Card(top: 8) {
            SectionHead(left: "Pelvic floor", right: "\(p.sets) a day this week")
            if let wk = wk {
                ARow(label: "Week \(s.prog.weeks.count)", detail: "\(p.name) · hold \(p.hold)s × \(p.reps) · \(p.flicks) flicks · \(p.sets) a day",
                     pct: "\(wk.done)/\(wk.target)", on: wk.done >= wk.target)
            }
            WeekRow(label: "Last 7", states: s.last7.map { $0.n >= $0.g ? .complete : ($0.n > 0 ? .partial : .missed) },
                    n: s.last7.filter { $0.n >= $0.g }.count, of: s.last7.count)
            if let g = s.wkGrade {
                ARow(label: "Grade", detail: "last \(g.n) day\(g.n == 1 ? "" : "s") · \(g.full) full, \(g.pass) pass, \(g.miss) missed",
                     pct: Fmt.fixed(g.pct, 0) + "%", on: g.pct >= Program.monthTarget, grade: g.grade)
            }
            ARow(label: "At goal", detail: "\(s.atGoal) of \(s.days) days · since \(lg.days.short(Program.kegStart))",
                 pct: Fmt.fixed(pct, 0) + "%", on: pct >= Program.monthTarget, grade: s.allGrade?.grade)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                StatTile(label: "Today", value: "\(s.today) of \(s.goal)", sub: s.today >= s.goal ? "goal met" : "sessions done")
                StatTile(label: "Streak", value: "\(s.streak) \(s.streak == 1 ? "day" : "days")", sub: "at the day’s goal")
                StatTile(label: "Sessions", value: Fmt.n(Double(s.total)), sub: "since \(lg.days.short(Program.kegStart))")
                StatTile(label: "Daily average", value: Fmt.fixed(s.avg, 1), sub: "sessions a day")
            }
            .padding(.top, 14)
            Note(text: "\(p.reps) squeezes held \(p.hold) seconds with an equal rest, then \(p.flicks) quick flicks, \(p.sets) times a day. " +
                 "Three building weeks, then a lighter one — " +
                 (nx.name == "Deload" ? "next week is a deload, lighter on purpose" : "next week is hold \(nx.hold)s × \(nx.reps), \(nx.sets) a day") +
                 ", once you finish at least half of this week’s \(wk?.target ?? 0) sessions. " +
                 "A+ means every day hit all \(p.sets); one short of the day’s count still passes at 80%, and today stays open until it is done. " +
                 "All three sitting. Breathe freely and keep your stomach, thighs and buttocks loose. " +
                 "Most men notice a change after six to eight weeks; stop if it hurts, and don’t practise by stopping your urine midstream.")
            LinkButton(title: "The year ahead →") { page = .plan }.padding(.top, 12)
        }
    }
}

/// A year of the pelvic floor program: weeks lived show what happened, the rest where it goes.
struct PlanView: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var c
    @Binding var page: Page
    let weeksShown = 52

    var body: some View {
        let lg = store.log, prog = lg.kegProgram, ws = prog.weeks, cur = ws.count - 1
        let thisYear = Days.parts(lg.days.today).y
        let lvlFor: (Int) -> Int = { i in i < ws.count ? ws[i].lvl : prog.level + (i - cur) }
        let tenAt = (max(0, cur)..<weeksShown).first { Log.kegLevelPlan(lvlFor($0)).hold >= 10 }
        func planDate(_ k: DayKey) -> String { lg.days.short(k) + (Days.parts(k).y != thisYear ? " \(Days.parts(k).y)" : "") }
        func planRange(_ a: DayKey, _ b: DayKey) -> String {
            let ya = Days.parts(a).y, yb = Days.parts(b).y
            return lg.days.short(a) + (ya != thisYear && ya != yb ? " \(ya)" : "") + " – " + planDate(b)
        }
        let p0 = prog.plan
        return VStack(alignment: .leading, spacing: 0) {
            Card {
                SectionHead(left: "Pelvic floor plan", right: "week \(ws.count) of \(weeksShown)")
                LinkButton(title: "← Back to Record") { page = .record }.padding(.bottom, 10)
                Text("This week: \(p0.name) · hold \(p0.hold)s × \(p0.reps), then \(p0.flicks) quick flicks, \(p0.sets) a day · \(prog.week?.done ?? 0) of \(prog.week?.target ?? 0) done")
                    .font(.system(size: 12)).foregroundStyle(c.muted)
                Note(text: "Three building weeks, then a lighter one. A week moves you up only if you finish at least half its sessions, so the dates below shift out if a week goes short — nothing here is a deadline." +
                     (tenAt.map { " Ten-second holds arrive in week \($0 + 1), the week of \(planDate(lg.days.shift(Program.kegStart, $0 * 7)))." } ?? ""))
            }
            ForEach(0..<(weeksShown / 4), id: \.self) { b in
                Card(top: 2) {
                    SectionHead(left: "Block \(b + 1)", right: "weeks \(b * 4 + 1)–\(min(weeksShown, b * 4 + 4))")
                    ForEach(b * 4..<min(weeksShown, b * 4 + 4), id: \.self) { i in
                        let pl = Log.kegLevelPlan(lvlFor(i)), sK = lg.days.shift(Program.kegStart, i * 7), eK = lg.days.shift(sK, 6)
                        let now = i == cur, past = i < cur, ok = past ? Double(ws[i].done) >= Double(ws[i].target) / 2 : true
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").font(.system(size: 12).monospacedDigit()).foregroundStyle(now ? c.brass : c.muted).frame(width: 26, alignment: .leading)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("hold \(pl.hold)s × \(pl.reps) · \(pl.flicks) flicks · \(pl.sets) a day")
                                        .font(.system(size: 13)).foregroundStyle(now ? c.brass : (pl.name == "Deload" ? c.muted : c.parchment))
                                        .opacity(i > cur ? 0.8 : 1)
                                    if pl.name != "Build" { Text(pl.name.uppercased()).font(.system(size: 10)).tracking(1).foregroundStyle(pl.name == "Deload" ? c.rust : c.muted) }
                                }
                                Text(planRange(sK, eK) + (now ? " · this week" : "")).font(.system(size: 11)).foregroundStyle(c.muted)
                            }
                            Spacer()
                            if past || now {
                                Text("\(ws[i].done)/\(ws[i].target)").font(.system(size: 12).monospacedDigit()).foregroundStyle(ok ? c.brass : c.rust)
                            }
                        }
                        .padding(.vertical, 9).padding(.horizontal, now ? 8 : 2)
                        .background(now ? c.track : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .hairline(c)
                    }
                }
            }
        }
    }
}
