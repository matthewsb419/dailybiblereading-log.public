import Foundation

/// Everything the Today card shows for one plan day, decided exactly as the website's render()
/// does: which trackers are asked, whether steps, the life goal and extra credit appear, and the
/// values they start with. A widget can read this too.
public struct TodayCard: Sendable {
    public struct Ask: Sendable, Identifiable {
        public let tracker: Tracker
        public let value: String?
        public var id: String { tracker.id }
    }

    public let day: Int
    public let plan: PlanDay
    public let entry: Entry
    public let isCurrent: Bool
    public let isNext: Bool
    public let stale: Bool
    /// The calendar day this card speaks for (nil when reading ahead).
    public let effDate: DayKey?
    public let dateLabel: String
    public let answers: [String: String]
    public let goal: (index: Int, text: String, read: Bool)?
    public let goalCount: Int
    public let quote: Quote
    public let quoteIndex: Int
    public let quoteCount: Int
    public let extraCredit: ExtraCredit?
    public let extraCreditText: String
    public let extraCreditLocked: Bool
    /// Trackers asked about yesterday and today; nil when the card asks none (reading ahead).
    public let yesterday: [Ask]?
    public let todayAsks: [Ask]?
    /// The steps box: the day it records and its current value.
    public let steps: (day: DayKey, value: Double?)?
    public let showsKeg: Bool
    public let answered: Int
}

extension Log {
    public func todayCard(_ day: Int) -> TodayCard {
        let plan = ReadingPlan.day(day)
        let entry = self.entry(day) ?? [:]
        let cur = currentDay, stale = isStale(entry), date = Log.str(entry, "date")
        let isCurrent = day == cur
        let effDate: DayKey? = isCurrent ? today : (stale || date.isEmpty ? nil : date)
        let dayOK = isCurrent || (!stale && !date.isEmpty && date < today)

        var goal: (Int, String, Bool)? = nil
        let gl = goals
        if !gl.isEmpty, dayOK, let eff = effDate {
            let gi = goalIndex(eff, gl.count)
            goal = (gi, gl[gi], Log.str(entry, "gr") == "yes")
        }

        let bank = quoteBank, qi = quoteIndex(effDate ?? today)

        let ecDay: DayKey? = (stale || date.isEmpty ? nil : date) ?? (isCurrent ? today : nil)
        let xc = ecStored(entry) ?? (dayOK ? ecFor(ecDay) : nil)
        let ecLocked = xc == nil && day > cur && today <= Program.ecEnd

        func asks(_ shift: Int) -> [TodayCard.Ask] {
            trackers.filter { t in
                guard t.shift == shift else { return false }
                if let wd = t.weekday { guard let eff = effDate, days.weekday(days.shift(eff, t.shift)) == wd else { return false } }
                if let st = t.start { guard let eff = effDate, days.shift(eff, t.shift) >= st else { return false } }
                return true
            }.map { t in
                var v: JSON? = stale ? nil : entry[t.id]
                if !Log.hasVal(t.id, v), let eff = effDate { v = markVal(t.id, days.shift(eff, t.shift)) }
                return .init(tracker: t, value: Log.hasVal(t.id, v) ? v?.string : nil)
            }
        }

        var steps: (DayKey, Double?)? = nil
        if dayOK, let eff = effDate {
            let dk = days.shift(eff, -1)
            if dk >= Program.stepStart && dk <= Program.stepEnd {
                var v: JSON? = stale ? nil : entry["st"]
                if !Log.hasVal("st", v) { v = markVal("st", dk) }
                steps = (dk, Log.hasVal("st", v) ? v?.number : nil)
            }
        }

        var answers: [String: String] = [:]
        for q in questions { answers[q.id] = Log.str(entry, q.id) }

        return TodayCard(day: day, plan: plan, entry: entry, isCurrent: isCurrent, isNext: day == nextUnloggedDay, stale: stale,
                         effDate: effDate, dateLabel: days.pretty(!date.isEmpty && !stale ? date : today),
                         answers: answers, goal: goal, goalCount: gl.count,
                         quote: bank[qi], quoteIndex: qi, quoteCount: bank.count,
                         extraCredit: xc, extraCreditText: Log.str(entry, "ec"), extraCreditLocked: ecLocked,
                         yesterday: dayOK ? asks(-1) : nil, todayAsks: dayOK ? asks(0) : nil,
                         steps: steps, showsKeg: isCurrent && today >= Program.kegStart, answered: answered(entry))
    }

    /// What the Today card currently holds. Anything not shown on the card is left as stored.
    public struct DayDraft: Sendable {
        public var answers: [String: String]
        public var trackers: [String: String?]       // only the trackers the card shows; nil = none picked
        public var steps: String?                     // nil when the card has no steps box
        public var goalRead: Bool?                    // nil when no life goal is shown
        public var extraCredit: (text: String, ch: Int, qi: Int)?
        public init(answers: [String: String] = [:], trackers: [String: String?] = [:], steps: String? = nil,
                    goalRead: Bool? = nil, extraCredit: (text: String, ch: Int, qi: Int)? = nil) {
            self.answers = answers; self.trackers = trackers; self.steps = steps
            self.goalRead = goalRead; self.extraCredit = extraCredit
        }
    }

    /// The website's writeDraft(): store the Today card for plan day `day`.
    public mutating func saveDay(_ day: Int, _ draft: DayDraft) {
        var e = entry(day) ?? ["day": .number(Double(day)), "date": .string(today)]
        if isStale(e) {
            for t in trackers { e[t.id] = nil }
            for k in ["gr", "st", "kg", "date"] { e[k] = nil }
        }
        var any = false
        for q in questions {
            guard let v = draft.answers[q.id] else { continue }
            e[q.id] = .string(v)
            if !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { any = true }
        }
        let base = Log.str(e, "date").isEmpty ? today : Log.str(e, "date")
        for t in trackers {
            guard let sel = draft.trackers[t.id] else { if e[t.id]?.truthy ?? false { any = true }; continue }
            if let sel = sel { e[t.id] = .string(sel); any = true } else { e[t.id] = nil }
            let mk = days.shift(base, t.shift)
            if markVal(t.id, mk) != nil { putMark(t.id, mk, "") }
        }
        if let text = draft.steps {
            if let sv = Log.parseSteps(text) { e["st"] = .number(sv); any = true } else { e["st"] = nil }
            let smk = days.shift(base, -1)
            if markVal("st", smk) != nil { putMark("st", smk, "") }
        } else if Log.hasVal("st", e["st"]) { any = true }
        if Log.hasVal("kg", e["kg"]) { any = true }
        if let read = draft.goalRead {
            if read { e["gr"] = "yes"; any = true } else { e["gr"] = nil }
        } else if e["gr"]?.truthy ?? false { any = true }
        if let xc = draft.extraCredit {
            if !xc.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                e["ec"] = .string(xc.text); e["ecCh"] = .number(Double(xc.ch)); e["ecQ"] = .number(Double(xc.qi)); any = true
            } else { e["ec"] = nil; e["ecCh"] = nil; e["ecQ"] = nil }
        } else if !Log.str(e, "ec").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { any = true }
        if any {
            if Log.str(e, "date").isEmpty { e["date"] = .string(today) }
            e["savedAt"] = .string(days.stamp())
            setEntry(day, e)
        } else {
            setEntry(day, nil)
        }
    }
}
