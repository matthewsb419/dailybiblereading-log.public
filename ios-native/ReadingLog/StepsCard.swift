import SwiftUI
import Charts
import ReadingLogCore

/// Steps · Valentine's Day: totals, the three charts, tiles, the 7-day grade and the daily log.
struct StepsCard: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var c
    @State private var range = "W"
    @State private var cumPick: DayKey?
    @State private var barPick: DayKey?
    @State private var needPick: Int?
    @State private var logOpen = false

    var body: some View {
        let lg = store.log, s = lg.stepStats, P = Program.self
        let stretch = s.total >= P.stepGoal
        let expPct = min(100, Double(s.days.count) / Double(s.span) * 100)
        let reach = s.total >= P.stepStretch ? "Done" : (s.hitDate.map { $0 <= P.stepEnd ? lg.days.short($0) : "After Feb 14" } ?? "—")

        Card(top: 8) {
            SectionHead(left: "Steps · Valentine’s Day", right: s.daysLeft > 0 ? plural(s.daysLeft, "day") + " left" : "Window closed")
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(Fmt.n(s.total)).font(.system(size: 34, weight: .semibold)).foregroundStyle(c.parchment)
                Text("steps since \(lg.days.short(P.stepStart))").font(.system(size: 13)).foregroundStyle(c.muted)
            }
            .padding(.top, 8)
            VStack(spacing: 0) {
                goalRow("Goal", P.stepGoal, s, expPct)
                goalRow("Stretch", P.stepStretch, s, expPct)
            }
            .padding(.top, 8)
            keys([("Taken", .solid), ("Goal pace", .dashed), ("Stretch pace", .dotted)])
            cumulative(s).frame(height: 180).padding(.top, 10)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "Daily average")
                    let b = bars(s)
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(b.count > 0 ? Fmt.n(b.sum / Double(b.count)) : "—").font(.system(size: 24, weight: .semibold)).foregroundStyle(c.parchment)
                        Text("steps").font(.system(size: 13)).foregroundStyle(c.muted)
                    }
                    Text(lg.days.short(b.list.first?.k ?? s.last) + " – " + lg.days.short(s.last) +
                         (b.count < b.inGoal ? " · \(b.count) of \(b.inGoal) days logged" : ""))
                        .font(.system(size: 13)).foregroundStyle(c.muted).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                HStack(spacing: 0) {
                    ForEach([("W", "Week"), ("M", "Month"), ("All", "All")], id: \.0) { r, t in
                        Button { range = r; barPick = nil } label: {
                            Text(t).font(.system(size: 12, weight: range == r ? .semibold : .regular))
                                .foregroundStyle(range == r ? c.ink : c.ghost).padding(.horizontal, 13).padding(.vertical, 5)
                                .background(range == r ? c.brass : .clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .clipShape(Capsule()).overlay(Capsule().stroke(c.line))
            }
            .padding(.top, 20)
            daily(s).frame(height: 160).padding(.top, 10)

            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Needed per day")
                Text("recalculated after every day’s count, for the days still left").font(.system(size: 13)).foregroundStyle(c.muted)
            }
            .padding(.top, 20)
            need(s).frame(height: 170).padding(.top, 10)
            keys([("For 1M", .solid), ("For 2M", .dotted)])

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                StatTile(label: "Needed per day", value: s.daysLeft > 0 && s.total < P.stepStretch ? Fmt.n(s.need) : "—", sub: stretch ? "for the stretch goal" : "for the goal")
                StatTile(label: "Daily average", value: s.logged > 0 ? Fmt.n(s.avg) : "—", sub: plural(s.logged, "day") + " logged")
                StatTile(label: "Best day", value: s.best > 0 ? Fmt.n(s.best) : "—", sub: s.bestK.map { lg.days.short($0) } ?? "")
                StatTile(label: "Streak", value: plural(s.streak, "day"), sub: "\(s.overPace) of \(s.counted) at \(Fmt.n(s.pace))+")
                StatTile(label: "By Feb 14", value: s.logged > 0 ? Fmt.compact(s.projected) : "—", sub: "at your daily average")
                StatTile(label: "Reach " + Fmt.compact(s.target), value: reach, sub: s.total >= P.stepStretch ? "stretch goal done" : "at your daily average")
            }
            .padding(.top, 14)

            if !s.week.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text("LAST 7").font(.system(size: 11)).tracking(1.1).foregroundStyle(c.muted).frame(width: 58, alignment: .leading)
                    HStack(spacing: 6) {
                        Text("\(Fmt.n(s.taken)) of \(Fmt.n(s.required)) needed").font(.system(size: 12)).foregroundStyle(c.muted)
                        Text(s.pass ? "PASS" : "SHORT \(Fmt.n(s.required - s.taken))").font(.system(size: 10, weight: .semibold)).tracking(1)
                            .foregroundStyle(s.pass ? c.brass : c.muted).padding(.horizontal, 7).padding(.vertical, 1)
                            .overlay(Capsule().stroke(s.pass ? c.brass : c.line))
                    }
                    Spacer()
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(Fmt.fixed(min(999, s.pct), 0) + "%").font(.serif(18)).foregroundStyle(s.pass ? c.brass : c.parchment)
                        Text(s.grade ?? "").font(.serif(15)).foregroundStyle(c.brass)
                    }
                }
                .padding(.vertical, 8).padding(.top, 14).hairline(c)
            }
            Note(text: "Last 7 is graded on what the goal needed each day when that week began: 100% is an A, and A+ means every day beat it. Days with no count are zeros — tap the day on the calendar to fill one in.")

            let rows = s.days.filter { $0.v != nil }.reversed()
            if !rows.isEmpty {
                DisclosureGroup(isExpanded: $logOpen) {
                    VStack(spacing: 0) {
                        ForEach(Array(rows), id: \.k) { x in
                            HStack {
                                Text(lg.days.short(x.k)).foregroundStyle(c.muted)
                                Spacer()
                                Text(Fmt.n(x.v ?? 0)).foregroundStyle(c.parchment)
                            }
                            .font(.system(size: 12).monospacedDigit()).padding(.vertical, 4).padding(.horizontal, 2).hairline(c)
                        }
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Daily log").font(.system(size: 12)).foregroundStyle(c.brass)
                }
                .padding(.top, 12)
            }
        }
    }

    // MARK: pieces

    func plural(_ n: Int, _ w: String) -> String { "\(n) \(w)\(n == 1 ? "" : "s")" }

    func goalRow(_ label: String, _ goal: Double, _ s: StepStats, _ expPct: Double) -> some View {
        let pct = min(100, s.total / goal * 100)
        return HStack(spacing: 10) {
            Text(label.uppercased()).font(.system(size: 11)).tracking(1.1).foregroundStyle(c.muted).frame(width: 58, alignment: .leading)
            Meter(pct: pct, marker: expPct)
            Text(Fmt.fixed(pct, pct < 10 ? 1 : 0) + "%").font(.system(size: 12).monospacedDigit()).foregroundStyle(c.parchment).frame(width: 50, alignment: .trailing)
            Text(Fmt.compact(goal)).font(.system(size: 11)).foregroundStyle(c.muted).frame(width: 28, alignment: .trailing)
        }
        .padding(.vertical, 6)
    }

    enum Dash { case solid, dashed, dotted }
    func keys(_ items: [(String, Dash)]) -> some View {
        HStack(spacing: 14) {
            ForEach(items, id: \.0) { t, d in
                HStack(spacing: 6) {
                    line(d).frame(width: 16, height: 2)
                    Text(t).font(.system(size: 11)).foregroundStyle(c.muted)
                }
            }
        }
        .padding(.top, 12)
    }
    @ViewBuilder func line(_ d: Dash) -> some View {
        switch d {
        case .solid: Rectangle().fill(c.brass)
        case .dashed: Rectangle().stroke(c.parchment, style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
        case .dotted: Rectangle().stroke(c.muted, style: StrokeStyle(lineWidth: 2, dash: [2, 3]))
        }
    }

    func date(_ k: DayKey) -> Date { store.log.days.date(k) }

    /// Running total against goal pace and stretch pace.
    func cumulative(_ s: StepStats) -> some View {
        let lg = store.log, P = Program.self, n = s.span
        var run = 0.0
        let cum = s.days.map { d -> (DayKey, Double) in run += d.v ?? 0; return (d.k, run) }
        let ymax = max(P.stepStretch, ((s.total * 1.05) / 250_000).rounded(.up) * 250_000)
        let end = lg.days.shift(P.stepStart, n - 1)
        let picked = cumPick.flatMap { k in lg.days.range(P.stepStart, end).firstIndex(of: k) }
        return Chart {
            LineMark(x: .value("Day", date(P.stepStart)), y: .value("Steps", P.stepStretch / Double(n)), series: .value("s", "stretch"))
                .foregroundStyle(c.muted).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
            LineMark(x: .value("Day", date(end)), y: .value("Steps", P.stepStretch), series: .value("s", "stretch"))
                .foregroundStyle(c.muted).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
            LineMark(x: .value("Day", date(P.stepStart)), y: .value("Steps", P.stepGoal / Double(n)), series: .value("s", "goal"))
                .foregroundStyle(c.parchment.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            LineMark(x: .value("Day", date(end)), y: .value("Steps", P.stepGoal), series: .value("s", "goal"))
                .foregroundStyle(c.parchment.opacity(0.7)).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            ForEach(cum, id: \.0) { k, v in
                AreaMark(x: .value("Day", date(k)), y: .value("Steps", v)).foregroundStyle(c.brass.opacity(0.1))
                LineMark(x: .value("Day", date(k)), y: .value("Steps", v), series: .value("s", "taken")).foregroundStyle(c.brass)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let last = cum.last {
                PointMark(x: .value("Day", date(last.0)), y: .value("Steps", last.1)).foregroundStyle(c.brass).symbolSize(50)
                    .annotation(position: .top) { Text(Fmt.compact(last.1)).font(.system(size: 10, weight: .semibold)).foregroundStyle(c.parchment) }
            }
            if let i = picked {
                let k = lg.days.shift(P.stepStart, i)
                RuleMark(x: .value("Day", date(k))).foregroundStyle(c.muted)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tip(lg.days.short(k), (i < cum.count ? [("taken", Fmt.n(cum[i].1), Dash.solid)] : []) +
                            [("goal pace", Fmt.n(P.stepGoal * Double(i + 1) / Double(n)), .dashed),
                             ("stretch pace", Fmt.n(P.stepStretch * Double(i + 1) / Double(n)), .dotted)])
                    }
            }
        }
        .chartYScale(domain: 0...ymax)
        .chartXScale(domain: date(P.stepStart)...date(end))
        .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)).foregroundStyle(c.muted) } }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { v in
            AxisGridLine().foregroundStyle(c.line)
            AxisValueLabel { if let d = v.as(Double.self) { Text(d == 0 ? "0" : Fmt.compact(d)).foregroundStyle(c.muted).font(.system(size: 10)) } }
        } }
        .chartXSelection(value: Binding(get: { cumPick.map(date) }, set: { cumPick = $0.map(lg.days.key) }))
    }

    struct Bars { let list: [StepDay]; let sum: Double; let count: Int; let inGoal: Int; let top: Double }
    func bars(_ s: StepStats) -> Bars {
        let lg = store.log, P = Program.self
        let n: Int, start: DayKey
        if range == "All" { start = P.stepStart; n = max(1, lg.days.count(P.stepStart, s.last)) }
        else { n = range == "M" ? 30 : 7; start = lg.days.shift(s.last, -(n - 1)) }
        var list: [StepDay] = [], sum = 0.0, cnt = 0, inGoal = 0, top = 0.0
        for i in 0..<n {
            let k = lg.days.shift(start, i), v = k >= P.stepStart ? s.map[k] : nil
            list.append(.init(k: k, v: v))
            if k >= P.stepStart { inGoal += 1 }
            if let v = v { sum += v; cnt += 1; top = max(top, v) }
        }
        return .init(list: list, sum: sum, count: cnt, inGoal: inGoal, top: top)
    }

    /// Steps per day, with the line each day now needs.
    func daily(_ s: StepStats) -> some View {
        let lg = store.log, b = bars(s)
        let need = s.daysLeft > 0 && s.total < Program.stepStretch ? s.need : 0
        let hi = max(b.top, need, 1000)
        let step: Double = hi <= 8000 ? 2000 : (hi <= 16000 ? 4000 : (hi <= 30000 ? 10000 : 20000))
        let ymax = (hi * 1.12 / step).rounded(.up) * step
        return Chart {
            ForEach(b.list, id: \.k) { d in
                if let v = d.v, v > 0 {
                    BarMark(x: .value("Day", d.k), y: .value("Steps", v), width: .ratio(0.8))
                        .foregroundStyle(barPick == d.k ? c.parchment : c.brass).clipShape(UnevenRoundedRectangle(topLeadingRadius: 4, topTrailingRadius: 4))
                }
            }
            if need > 0 {
                RuleMark(y: .value("Need", need)).foregroundStyle(c.parchment.opacity(0.65)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) { Text("\(Fmt.n(need)) needed").font(.system(size: 10)).foregroundStyle(c.muted) }
            }
            if let k = barPick, let d = b.list.first(where: { $0.k == k }) {
                RuleMark(x: .value("Day", k)).foregroundStyle(.clear)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tip(lg.days.format(k, "EEE MMM d"), d.v.map { [("steps", Fmt.n($0), Dash.solid)] } ?? [("no count", "—", .solid)])
                    }
            }
        }
        .chartYScale(domain: 0...ymax)
        .chartXAxis {
            AxisMarks(values: b.list.map(\.k)) { v in
                if let k = v.as(String.self), let lab = barLabel(k, b.list) { AxisValueLabel { Text(lab).font(.system(size: 10)).foregroundStyle(c.muted) } }
            }
        }
        .chartYAxis { AxisMarks(position: .leading, values: .stride(by: step)) { v in
            AxisGridLine().foregroundStyle(c.line)
            AxisValueLabel { if let d = v.as(Double.self) { Text(d == 0 ? "0" : Fmt.compact(d)).foregroundStyle(c.muted).font(.system(size: 10)) } }
        } }
        .chartXSelection(value: $barPick)
    }
    func barLabel(_ k: DayKey, _ list: [StepDay]) -> String? {
        let lg = store.log, n = list.count, j = list.firstIndex { $0.k == k } ?? 0
        if range == "W" { return String(lg.days.format(k, "EEEEE")) }
        if range == "M" || n <= 31 { return (n - 1 - j) % 7 == 0 ? lg.days.short(k) : nil }
        return k.hasSuffix("-01") ? lg.days.format(k, "MMM") : nil
    }

    /// What every remaining day needs, recomputed after each day's count.
    func need(_ s: StepStats) -> some View {
        let lg = store.log, pts = lg.needSeries(s)
        let vals = pts.flatMap { [$0.g, $0.s] }
        var lo = vals.min() ?? 0
        let hi = vals.max() ?? 1
        if hi - lo < hi * 0.08 { lo = hi * 0.9 }
        let ymin = max(0, lo * 0.92), ymax = hi * 1.06 > 0 ? hi * 1.06 : 1
        let idx = Array(pts.indices)
        return Chart {
            ForEach(idx, id: \.self) { i in
                LineMark(x: .value("i", i), y: .value("Need", pts[i].s), series: .value("s", "2M")).foregroundStyle(c.muted)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [2, 4]))
                LineMark(x: .value("i", i), y: .value("Need", pts[i].g), series: .value("s", "1M")).foregroundStyle(c.brass)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            if let last = idx.last {
                PointMark(x: .value("i", last), y: .value("Need", pts[last].g)).foregroundStyle(c.brass).symbolSize(50)
                    .annotation(position: .top, alignment: .trailing) { Text(Fmt.n(pts[last].g)).font(.system(size: 10, weight: .semibold)).foregroundStyle(c.parchment) }
            }
            if let i = needPick.map({ max(0, min(pts.count - 1, $0)) }) {
                let p = pts[i]
                RuleMark(x: .value("i", i)).foregroundStyle(c.muted)
                    .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tip(p.start ? "Before the first day" : lg.days.short(p.k),
                            (p.start ? [] : [("steps that day", p.v.map(Fmt.n) ?? "—", Dash.solid)]) +
                            [("then needed for 1M", Fmt.n(p.g), .solid), ("for 2M", Fmt.n(p.s), .dotted)])
                    }
            }
        }
        .chartYScale(domain: ymin...ymax)
        .chartXScale(domain: 0...max(1, pts.count - 1))
        .chartXAxis {
            AxisMarks(values: idx.filter { $0 > 0 && pts[$0].k.hasSuffix("-01") }) { v in
                if let i = v.as(Int.self) { AxisValueLabel { Text(lg.days.format(pts[i].k, "MMM")).font(.system(size: 10)).foregroundStyle(c.muted) } }
            }
        }
        .chartYAxis { AxisMarks(position: .leading, values: .automatic(desiredCount: 5)) { v in
            AxisGridLine().foregroundStyle(c.line)
            AxisValueLabel { if let d = v.as(Double.self) { Text(Fmt.compact(d)).foregroundStyle(c.muted).font(.system(size: 10)) } }
        } }
        .chartXSelection(value: $needPick)
    }

    func tip(_ title: String, _ rows: [(String, String, Dash)]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 11)).foregroundStyle(c.muted)
            ForEach(rows, id: \.0) { label, value, d in
                HStack(spacing: 6) {
                    line(d).frame(width: 16, height: 2)
                    Text(value).font(.system(size: 13, weight: .semibold).monospacedDigit()).foregroundStyle(c.parchment)
                    Text(label).font(.system(size: 11)).foregroundStyle(c.muted)
                }
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 6)
        .background(c.ink, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(c.line))
    }
}
