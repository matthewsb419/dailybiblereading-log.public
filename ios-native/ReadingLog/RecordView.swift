import SwiftUI
import ReadingLogCore

struct RecordView: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var c
    @Binding var page: Page
    @State private var viewY = 0
    @State private var viewM = 0
    @State private var pick: DayKey?

    var body: some View {
        let lg = store.log
        VStack(alignment: .leading, spacing: 0) {
            if lg.allMonths.isEmpty {
                Card { Text("Nothing scored yet. Answer all three questions on a day and it starts counting.").font(.system(size: 14)).foregroundStyle(c.muted) }
            } else {
                HabitsCard()
                MonthCard(viewY: $viewY, viewM: $viewM, pick: $pick)
                lastSeven(lg)
                allTime(lg)
                if lg.days.today > Program.stepStart { StepsCard() }
                if lg.days.today >= Program.kegStart { KegCard(page: $page) }
                byMonth(lg)
            }
            extraCredit(lg)
        }
        .onAppear { let n = Days.parts(lg.days.today); viewY = n.y; viewM = n.m }
    }

    struct TrackerInfo { let t: Tracker; let map: [DayKey: Mark]; let first: DayKey?; let now: DayKey }
    func infos(_ lg: Log) -> [TrackerInfo] {
        trackers.map { t in
            let map = lg.trackerMap(t.id)
            return TrackerInfo(t: t, map: map, first: Log.first(map), now: lg.trackerNow(t.id))
        }
    }

    func lastSeven(_ lg: Log) -> some View {
        Card {
            SectionHead(left: "Last 7 days")
            if let wk = lg.weekStats {
                WeekRow(label: "Reading", states: wk.days.map(\.state), n: wk.complete, of: wk.elapsed, pct: wk.pct)
            }
            ForEach(infos(lg), id: \.t.id) { i in
                if let f = i.first {
                    let w = lg.trackerWeek(i.map, first: f, now: i.now, weekday: i.t.weekday)
                    // P, M and J always show; the newer ones once they have a day in the window
                    if ["p", "m", "j"].contains(i.t.id) || w.elapsed > 0 {
                        WeekRow(label: i.t.label, states: w.days.map(\.state), n: w.n, of: w.elapsed, pct: w.pct)
                    }
                }
            }
            Note(text: "Rolling seven days, not Sunday-to-Saturday. P and M run a day behind — each answer lands on the day it describes. J and H are for the day itself. G is Mondays only. MG is Monday night, answered Tuesday; a week the group doesn’t meet is left out.")
        }
    }

    func allTime(_ lg: Log) -> some View {
        let dm = lg.dateMap
        let total = dm.values.filter { lg.isComplete($0.entry) }.count
        let start = lg.firstDate ?? lg.days.today
        let elapsed = lg.days.between(start, lg.days.today) + 1
        func row(_ label: String, _ n: Int, _ el: Int, _ since: DayKey, _ unit: String = "days") -> ARow {
            let pct = el > 0 ? Double(n) / Double(el) * 100 : 0
            return ARow(label: label, detail: "\(n) of \(el) \(unit) · since \(lg.days.short(since))", pct: Fmt.fixed(pct, 1) + "%",
                        on: pct >= Program.monthTarget, grade: el < Program.gradeFloor ? "—" : Program.grade(pct))
        }
        return Card {
            SectionHead(left: "All time")
            row("Reading", total, elapsed, start)
            ForEach(infos(lg), id: \.t.id) { i in
                if let f = i.first {
                    let clean = i.map.values.filter { $0 == .good }.count
                    switch i.t.id {
                    case "g": row("G", clean, lg.days.count(f, lg.days.today, weekday: 1), f, "Mondays")
                    case "mg":
                        let to = lg.days.yesterday
                        let done = i.map.filter { $0.key <= to && $0.value == .good }.count
                        let off = i.map.filter { $0.key <= to && $0.value == .off }.count
                        let el = lg.days.count(f, to, weekday: 1) - off
                        if el > 0 { row("MG", done, el, f, "Mondays") }
                    default: row(i.t.label, clean, lg.days.between(f, i.now) + 1, f)
                    }
                }
            }
            Meter(pct: Double(total) / Double(Program.yearGoal) * 100, marker: nil, height: 6).padding(.top, 16)
            Text("\(total) of \(Program.yearGoal) reading days toward the year").font(.system(size: 13)).foregroundStyle(c.muted).padding(.top, 8)
        }
    }

    func byMonth(_ lg: Log) -> some View {
        let ti = infos(lg)
        let order = ["p", "m", "j", "h", "g", "mg"]
        func cell(_ pct: Double?, _ el: Int) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if let p = pct {
                    Text(Fmt.fixed(p, 0) + "%").foregroundStyle(p >= Program.monthTarget ? c.brass : c.muted)
                    Text(el < Program.gradeFloor ? "—" : Program.grade(p)).font(.serif(13)).foregroundStyle(c.brass)
                } else { Text("—").foregroundStyle(c.muted) }
            }
            .font(.system(size: 12).monospacedDigit()).frame(width: 52, alignment: .trailing)
        }
        return VStack(alignment: .leading, spacing: 0) {
            SectionHead(left: "By month").padding(.top, 8)
            ScrollView(.horizontal, showsIndicators: false) {
                VStack(spacing: 0) {
                    HStack(spacing: 3) {
                        Text("").frame(width: 76, alignment: .leading)
                        ForEach(["Read", "P", "M", "J", "H", "G", "MG"], id: \.self) {
                            Text($0.uppercased()).font(.system(size: 10)).tracking(1).foregroundStyle(c.muted).frame(width: 52, alignment: .trailing)
                        }
                    }
                    .padding(.bottom, 2)
                    ForEach(lg.allMonths, id: \.m) { ms in
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(lg.days.monthShort(ms.y, ms.m)).font(.system(size: 13)).foregroundStyle(c.parchment).frame(width: 76, alignment: .leading)
                            cell(ms.pct, ms.elapsed)
                            ForEach(order, id: \.self) { id in
                                let i = ti.first { $0.t.id == id }!
                                let st = i.first.flatMap { lg.trackerMonth(i.map, first: $0, ms.y, ms.m, now: i.now, weekday: i.t.weekday) }
                                cell(st?.pct, st?.elapsed ?? 0)
                            }
                        }
                        .padding(.vertical, 11).padding(.horizontal, 2).hairline(c)
                    }
                }
            }
        }
    }

    @ViewBuilder func extraCredit(_ lg: Log) -> some View {
        let el = lg.ecDays
        if el > 0 {
            let em = lg.ecMap
            let done = em.keys.filter { $0 >= Program.ecStart && $0 <= Program.ecEnd }.count
            let pct = Double(done) / Double(el) * 100
            let week = (0...6).reversed().map { lg.days.shift(lg.days.today, -$0) }.filter { $0 >= Program.ecStart && $0 <= Program.ecEnd }
            let total = lg.ecTotalDays, leftDays = total - el
            Card(top: 8) {
                SectionHead(left: "Extra credit · 1 Timothy", right: leftDays > 0 ? "\(leftDays) day\(leftDays == 1 ? "" : "s") to Christmas Eve" : "Run complete")
                WeekRow(label: "Last 7", states: week.map { em[$0] != nil ? .complete : .missed }, n: week.filter { em[$0] != nil }.count, of: week.count)
                HStack(alignment: .firstTextBaseline) {
                    Text("\(done) of \(el) days · since \(lg.days.short(Program.ecStart))").font(.system(size: 12)).foregroundStyle(c.muted)
                    Spacer()
                    Text(Fmt.fixed(pct, 0) + "%").font(.serif(18)).foregroundStyle(pct >= Program.monthTarget ? c.brass : c.parchment)
                }
                .padding(.top, 4)
                Meter(pct: Double(el) / Double(total) * 100, marker: nil, height: 6).padding(.top, 14)
                Text("Day \(min(el, total)) of \(total) in the cycle").font(.system(size: 13)).foregroundStyle(c.muted).padding(.top, 8)
                Note(text: "Optional, so it is not graded and does not count toward the percentages above. One chapter a day, 1 through 6 on repeat, with a new question each time a chapter comes back around.")
            }
        }
    }
}

struct HabitsCard: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var c

    var body: some View {
        let lg = store.log, defs = lg.habitDefs, today = lg.days.today, yest = lg.days.yesterday
        if !defs.isEmpty {
            let live = defs.filter { $0.to == nil || today <= $0.to! }
            let wk = lg.habitWindow(defs, from: lg.days.shift(yest, -6), to: yest)
            let all = lg.habitWindow(defs, from: "1900-01-01", to: yest)
            let since = defs.map(\.from).min() ?? today
            Card {
                SectionHead(left: "Daily habits", right: "\(live.count) tracked")
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(wk.n > 0 ? Fmt.fixed(wk.pct, 0) + "%" : "—").font(.system(size: 34, weight: .semibold)).foregroundStyle(c.parchment)
                    Text("overall, last 7 days" + (wk.n > 0 ? " · " + Program.grade(wk.pct) : "")).font(.system(size: 13)).foregroundStyle(c.muted)
                }
                .padding(.top, 8).padding(.bottom, 2)
                if wk.n > 0 {
                    VStack(spacing: 0) {
                        ForEach(wk.per, id: \.id) { x in
                            BarRow(label: x.label, pct: x.pct, grade: x.n < 3 ? "—" : Program.grade(x.pct), digits: 0)
                        }
                    }
                    .padding(.top, 8)
                }
                if all.n > 0 {
                    ARow(label: "All time", detail: "\(all.n) habit\(all.n == 1 ? "" : "s") · since \(lg.days.short(since))",
                         pct: Fmt.fixed(all.pct, 0) + "%", on: all.pct >= Program.monthTarget, grade: Program.grade(all.pct))
                }
                Note(text: "Every habit counts the same: each is scored over its own days — Mondays only for G and MG, steps against the pace the walking goal needs, sessions against that week’s count — and the percentages are averaged. Today isn’t counted until it closes, and a habit joins the score the day it starts.")
            }
        }
    }
}

/// The month view: bars for each habit, the calendar with pips, and the fill-in sheet for a tapped day.
struct MonthCard: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var c
    @Binding var viewY: Int
    @Binding var viewM: Int
    @Binding var pick: DayKey?
    @State private var stepsText = ""
    @State private var kegText = ""
    @FocusState private var typing: Bool

    var body: some View {
        let lg = store.log, today = lg.days.today
        let maps = Dictionary(uniqueKeysWithValues: trackers.map { ($0.id, lg.trackerMap($0.id)) })
        let firsts = maps.mapValues { Log.first($0) }
        let start = lg.firstDate ?? today
        let minKey = ([start] + firsts.values.compactMap { $0 }).min()!
        let minP = Days.parts(minKey), nowP = Days.parts(today)
        let y = viewY == 0 ? nowP.y : viewY, m = viewM == 0 ? nowP.m : viewM
        let atMin = (y, m) <= (minP.y, minP.m), atMax = (y, m) >= (nowP.y, nowP.m)
        let sP = Days.parts(start)
        let tm = (y, m) >= (sP.y, sP.m) ? lg.monthStats(y, m) : nil
        func ms(_ id: String) -> Log.TrackerStats? {
            guard let f = firsts[id] ?? nil, let t = tracker(id) else { return nil }
            return lg.trackerMonth(maps[id]!, first: f, y, m, now: lg.trackerNow(id), weekday: t.weekday)
        }
        func grade(_ s: Log.TrackerStats?) -> String? { s.map { $0.elapsed < Program.gradeFloor ? "—" : Program.grade($0.pct) } }

        return Card {
            HStack {
                navButton("chevron.left", disabled: atMin) { move(-1, y, m) }
                Spacer()
                Eyebrow(text: lg.days.monthName(y, m))
                Spacer()
                navButton("chevron.right", disabled: atMax) { move(1, y, m) }
            }
            VStack(spacing: 0) {
                BarRow(label: "Reading", pct: tm?.pct, grade: tm.map { $0.elapsed < Program.gradeFloor ? "—" : Program.grade($0.pct) })
                ForEach(["p", "m", "j", "h", "g", "mg"], id: \.self) { id in
                    BarRow(label: tracker(id)!.label, pct: ms(id)?.pct, grade: grade(ms(id)), alt: true)
                }
            }
            .padding(.vertical, 8)

            let cols = Array(repeating: GridItem(.flexible(), spacing: 5), count: 7)
            LazyVGrid(columns: cols, spacing: 5) {
                ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { _, d in
                    Text(d).font(.system(size: 10)).tracking(0.8).foregroundStyle(c.muted.opacity(0.75))
                }
            }
            .padding(.top, 16)
            LazyVGrid(columns: cols, spacing: 5) {
                ForEach(0..<lg.days.weekday(Days.make(y, m, 1)), id: \.self) { i in Color.clear.aspectRatio(1, contentMode: .fit).id("lead\(i)") }
                let pdm = lg.planDayMap, cur = lg.currentDay
                ForEach(lg.days.range(Days.make(y, m, 1), Days.make(y, m, lg.days.daysInMonth(y, m))), id: \.self) { dk in
                    dayCell(dk, d: Days.parts(dk).d, tm: tm, maps: maps, firsts: firsts, pdm: pdm, cur: cur, minKey: minKey)
                }
            }
            .padding(.top, 6).padding(.bottom, 12)

            if let p = pick, p.hasPrefix(Days.make(y, m, 1).prefix(7)) { fillIn(p, maps: maps) }

            FlowRow(spacing: 14) {
                legend(AnyView(RoundedRectangle(cornerRadius: 3).fill(c.brass).frame(width: 10, height: 10)), "All three")
                legend(AnyView(RoundedRectangle(cornerRadius: 3).stroke(c.brass).frame(width: 10, height: 10)), "Partial")
                legend(AnyView(RoundedRectangle(cornerRadius: 3).stroke(c.line).frame(width: 10, height: 10)), "Missed")
                legend(AnyView(Pip(label: "P", mark: .good)), "No")
                legend(AnyView(Pip(label: "M", mark: .bad)), "Yes")
                legend(AnyView(Pip(label: "J", mark: .good)), "Yes")
                legend(AnyView(Pip(label: "H", mark: .good)), "How We Feel")
                legend(AnyView(Text("G").font(.system(size: 9, weight: .bold)).foregroundStyle(c.brass)), "Mondays")
                legend(AnyView(Text("MG").font(.system(size: 9, weight: .bold)).foregroundStyle(c.brass)), "Men’s group")
                legend(AnyView(Text("8").font(.system(size: 8, weight: .medium)).foregroundStyle(c.muted).padding(.horizontal, 3).overlay(RoundedRectangle(cornerRadius: 3).stroke(c.line))), "Reading day")
            }
            Note(text: "Tap a day to fill in or fix its P, M, J, H and steps (G and MG on Mondays).")
        }
    }

    func legend(_ icon: AnyView, _ text: String) -> some View {
        HStack(spacing: 5) { icon; Text(text).font(.system(size: 11)).foregroundStyle(c.muted) }
    }

    func navButton(_ icon: String, disabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(c.muted).frame(width: 28, height: 28)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(c.line))
        }
        .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.25 : 1)
    }
    func move(_ by: Int, _ y: Int, _ m: Int) {
        var ny = y, nm = m + by
        if nm < 1 { nm = 12; ny -= 1 }
        if nm > 12 { nm = 1; ny += 1 }
        viewY = ny; viewM = nm; pick = nil
    }

    func dayCell(_ dk: DayKey, d: Int, tm: Log.MonthStats?, maps: [String: [DayKey: Mark]], firsts: [String: DayKey?],
                 pdm: [DayKey: Int], cur: Int, minKey: DayKey) -> some View {
        let lg = store.log, today = lg.days.today
        let anyT = trackers.contains { maps[$0.id]?[dk] != nil }
        let inRange = tm.map { d >= $0.first && d <= $0.last } ?? false
        let state: String = inRange ? (tm!.marks[d]?.rawValue ?? "missed") : (anyT ? "missed" : "out")
        let out = state == "out"
        let complete = state == "complete"
        let pdn = pdm[dk] ?? (dk == today && !out ? cur : 0)
        let isMon = lg.days.weekday(dk) == 1
        let canEdit = dk <= today && dk >= minKey
        let hF = firsts["h"] ?? nil
        return Color.clear.aspectRatio(1, contentMode: .fit).overlay { GeometryReader { geo in
            let pip = min(11, (geo.size.width - 4) / 4 - 2)
            ZStack {
            RoundedRectangle(cornerRadius: 5).fill(complete ? c.brass : .clear)
            RoundedRectangle(cornerRadius: 5).stroke(out ? .clear : (complete || state == "partial" ? c.brass : c.line))
            if pick == dk { RoundedRectangle(cornerRadius: 5).stroke(c.parchment, lineWidth: 2).padding(-2) }
            Text("\(d)").font(.system(size: 11, weight: complete ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(complete ? c.ink : (out ? c.outnum : (state == "partial" ? c.brass : c.daynum)))
                .offset(y: out ? 0 : -4)
            if pdn > 0 {
                Text("\(pdn)").font(.system(size: 9, weight: .medium)).foregroundStyle(complete ? c.ink.opacity(0.7) : (state == "partial" ? c.brass : c.muted))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing).padding(.top, 3).padding(.trailing, 4)
            }
            if isMon && !out {
                HStack(spacing: 3) {
                    corner("G", maps["g"]?[dk], first: firsts["g"] ?? nil, dk: dk, complete: complete)
                    corner("MG", maps["mg"]?[dk], first: firsts["mg"] ?? nil, dk: dk, complete: complete)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading).padding(.top, 3).padding(.leading, 4)
            }
            if !out {
                HStack(spacing: 2) {
                    Pip(label: "P", mark: maps["p"]?[dk], inverted: complete, size: pip)
                    Pip(label: "M", mark: maps["m"]?[dk], inverted: complete, size: pip)
                    Pip(label: "J", mark: maps["j"]?[dk], inverted: complete, size: pip)
                    if let h = hF, dk >= h { Pip(label: "H", mark: maps["h"]?[dk], inverted: complete, size: pip) }
                }
                .frame(maxHeight: .infinity, alignment: .bottom).padding(.bottom, 3)
            }
        }
        } }
        .aspectRatio(1, contentMode: .fit)
        .contentShape(Rectangle())
        .onTapGesture {
            guard canEdit else { return }
            pick = pick == dk ? nil : dk
            stepsText = lg.stepMap[dk].map(Fmt.n) ?? ""
            kegText = lg.kegMap[dk].map(String.init) ?? ""
        }
        .accessibilityLabel(canEdit ? "Fill in \(lg.days.pretty(dk))" : "\(d)")
    }

    @ViewBuilder func corner(_ label: String, _ v: Mark?, first: DayKey?, dk: DayKey, complete: Bool) -> some View {
        if let f = first, dk >= f {
            let color: Color = v == .good ? (complete ? c.ink : c.brass) : (v == .bad ? (complete ? c.rustdeep : c.rust) : (complete ? c.ink.opacity(0.55) : c.ghost))
            Text(label).font(.system(size: 9, weight: .bold)).foregroundStyle(color)
                .strikethrough(v == .off).opacity(v == .off ? 0.6 : 1)
        }
    }

    func fillIn(_ dk: DayKey, maps: [String: [DayKey: Mark]]) -> some View {
        let lg = store.log, today = lg.days.today, yk = lg.days.yesterday, wd = lg.days.weekday(dk)
        return VStack(alignment: .leading, spacing: 10) {
            HStack { Eyebrow(text: lg.days.pretty(dk)); Spacer(); LinkButton(title: "Done") { pick = nil } }
            FlowRow(spacing: 18) {
                ForEach(trackers.filter { t in
                    !(dk > (t.shift < 0 ? yk : today)) && !(t.start.map { dk < $0 } ?? false) && !(t.weekday.map { wd != $0 } ?? false)
                }) { t in
                    let b = maps[t.id]?[dk]
                    let v: String? = b == .good ? t.good : (b == .bad ? t.bad : (b == .off ? "off" : nil))
                    TrackerToggle(tracker: t, value: v) { nv in store.edit { $0.setMark(t.id, dk, nv.map { .string($0) } ?? "") } }
                }
                if dk >= Program.stepStart && dk <= Program.stepEnd && dk <= yk {
                    numberBox("Steps", $stepsText, width: 104) {
                        let n = Log.parseSteps(stepsText)
                        store.edit { $0.setMark("st", dk, n.map { .number($0) } ?? "") }
                        stepsText = n.map(Fmt.n) ?? ""
                    }
                }
                if dk >= Program.kegStart && dk <= today {
                    numberBox("Sessions", $kegText, width: 72) {
                        let n = Log.parseKeg(kegText)
                        store.edit { $0.setMark("kg", dk, n.map { .number(Double($0)) } ?? "") }
                        kegText = n.map(String.init) ?? ""
                    }
                }
            }
            if dk == today { Note(text: "P, M, MG and steps for today get answered tomorrow.") }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(c.track, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.brass))
        .padding(.bottom, 14)
    }

    func numberBox(_ label: String, _ text: Binding<String>, width: CGFloat, commit: @escaping () -> Void) -> some View {
        HStack(spacing: 7) {
            Text(label).font(.system(size: 12)).foregroundStyle(c.muted)
            TextField("0", text: text)
                .keyboardType(.numberPad).focused($typing)
                .font(.system(size: 13).monospacedDigit()).foregroundStyle(c.parchment)
                .padding(.horizontal, 12).padding(.vertical, 5).frame(width: width)
                .background(c.ink, in: Capsule()).overlay(Capsule().stroke(c.line))
                .onSubmit(commit)
                .onChange(of: typing) { was, now in if was && !now { commit() } }
        }
    }
}

/// A tiny lettered circle for one tracker on one day: filled for a win, red for a slip.
struct Pip: View {
    @Environment(\.palette) private var c
    let label: String
    let mark: Mark?
    var inverted = false
    var size: CGFloat = 11
    var body: some View {
        let fill: Color = mark == .good ? (inverted ? c.ink : c.brass) : (mark == .bad ? (inverted ? c.rustdeep : c.rust) : .clear)
        let stroke: Color = mark == .good ? fill : (mark == .bad ? fill : (inverted ? c.pipinvline : c.pipline))
        let text: Color = mark == .good ? (inverted ? c.brass : c.ink) : (mark == .bad ? c.parchment : (inverted ? c.pipinvtext : c.piptext))
        Text(label).font(.system(size: size * 0.64, weight: .semibold)).foregroundStyle(text)
            .frame(width: size, height: size).background(fill, in: Circle()).overlay(Circle().stroke(stroke, lineWidth: 1))
    }
}
