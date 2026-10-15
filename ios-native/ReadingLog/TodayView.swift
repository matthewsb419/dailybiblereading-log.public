import SwiftUI
import UniformTypeIdentifiers
import ReadingLogCore

/// What's typed on the Today card, held while it's being edited and saved shortly after.
struct DayInputs: Equatable {
    var answers: [String: String] = [:]
    var picks: [String: String?] = [:]
    var steps = ""
    var goalRead = false
    var ec = ""

    init() {}
    init(_ card: TodayCard) {
        answers = card.answers
        for a in (card.yesterday ?? []) + (card.todayAsks ?? []) { picks[a.id] = .some(a.value) }
        steps = card.steps?.value.map(Fmt.n) ?? ""
        goalRead = card.goal?.read ?? false
        ec = card.extraCreditText
    }

    /// Only what the card shows goes in; everything else stays as stored.
    func draft(for card: TodayCard) -> Log.DayDraft {
        var shown: [String: String?] = [:]
        for a in (card.yesterday ?? []) + (card.todayAsks ?? []) { shown[a.id] = .some(picks[a.id] ?? nil) }
        return Log.DayDraft(answers: answers, trackers: shown, steps: card.steps == nil ? nil : steps,
                            goalRead: card.goal == nil ? nil : goalRead,
                            extraCredit: card.extraCredit.map { (ec, $0.ch, $0.qi) })
    }
}

struct TodayView: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var c
    @Binding var viewDay: Int
    @State private var inputs = DayInputs()
    @State private var loadedDay = 0
    @State private var saveTask: Task<Void, Never>?
    @State private var dirty = false
    @FocusState private var focused: Bool
    @State private var syncOpen = false
    @State private var importing = false
    @State private var sharing: SharedFile?
    @State private var healthBusy = false

    var card: TodayCard { store.log.todayCard(max(1, viewDay)) }

    var body: some View {
        let card = self.card
        VStack(alignment: .leading, spacing: 0) {
            Card {
                top(card)
                assignment(card)
                ForEach(questions) { q in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(q.prompt).font(.system(size: 13)).foregroundStyle(c.muted)
                        WriteBox(text: binding(\.answers, q.id)).focused($focused).accessibilityIdentifier("answer-\(q.id)")
                    }
                    .padding(.bottom, 16)
                }
                if let g = card.goal { goalBox(g, count: card.goalCount) }
                encouragement(card)
                extraCredit(card)
                if card.yesterday != nil { trackers(card) }
                if card.showsKeg { KegRow().padding(.top, 16) }
                footer(card)
            }
            recent
            actions
            Text(footText).font(.system(size: 11)).foregroundStyle(c.muted).padding(.top, 12)
            LinkButton(title: "Sync settings") { syncOpen = true }.padding(.top, 4)
        }
        .onAppear { reload(force: true) }
        .onChange(of: viewDay) { old, _ in saveNow(day: old); reload(force: true) }
        .onChange(of: store.log.state) { _, _ in reload(force: false) }
        .onChange(of: focused) { _, f in if !f { saveNow(day: viewDay); inputs.steps = Log.parseSteps(inputs.steps).map(Fmt.n) ?? "" } }
        .onDisappear { saveNow(day: viewDay) }
        .sheet(isPresented: $syncOpen) { SyncSheet() }
        .sheet(item: $sharing) { ShareSheet(url: $0.url) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in restore(result) }
    }

    // MARK: pieces

    func top(_ card: TodayCard) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(card.dateLabel).font(.system(size: 15, weight: .semibold)).foregroundStyle(c.parchment)
                if !card.isNext { LinkButton(title: "Go to next unread") { go(store.log.nextUnloggedDay) } }
            }
            Spacer()
            HStack(spacing: 6) {
                stepButton("minus", disabled: viewDay <= 1) { go(viewDay - 1) }
                Text("Day \(viewDay)").font(.system(size: 11)).foregroundStyle(c.muted).frame(minWidth: 52)
                stepButton("plus", disabled: viewDay >= ReadingPlan.count) { go(viewDay + 1) }
            }
        }
    }
    func stepButton(_ icon: String, disabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 13)).foregroundStyle(c.parchment).frame(width: 30, height: 30)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(c.line))
        }
        .buttonStyle(.plain).disabled(disabled).opacity(disabled ? 0.3 : 1)
        .accessibilityLabel(icon == "minus" ? "Previous day" : "Next day")
    }

    func assignment(_ card: TodayCard) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(card.plan.read).font(.serif(27)).foregroundStyle(c.brass)
            Text("~\(card.plan.verses) verses · about \(card.plan.min) minutes").font(.system(size: 12)).foregroundStyle(c.muted)
        }
        .padding(.top, 16).padding(.bottom, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairline(c)
        .padding(.bottom, 20)
    }

    func goalBox(_ g: (index: Int, text: String, read: Bool), count: Int) -> some View {
        let read = inputs.goalRead
        return VStack(alignment: .leading, spacing: 0) {
            HStack { Eyebrow(text: "Life goal", color: read ? c.brass : nil); Spacer(); Text("\(g.index + 1) of \(count)").font(.system(size: 11)).foregroundStyle(c.muted) }
            Text(g.text).font(.serif(17)).foregroundStyle(c.parchment).padding(.top, 8).padding(.bottom, 10)
            Button {
                inputs.goalRead.toggle(); saveNow(day: viewDay)
            } label: {
                Text(read ? "Read ✓" : "Mark as read").font(.system(size: 12, weight: read ? .semibold : .regular))
                    .foregroundStyle(read ? c.ink : c.muted).padding(.horizontal, 13).padding(.vertical, 5)
                    .background(read ? c.brass : .clear, in: Capsule()).overlay(Capsule().stroke(read ? c.brass : c.line))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(c.track, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(read ? c.brass : c.line))
        .padding(.top, 4).padding(.bottom, 16)
    }

    func encouragement(_ card: TodayCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Eyebrow(text: "Encouragement"); Spacer()
                Text("\(Content.shared.categoryName(card.quote.c)) · \(card.quoteIndex + 1) of \(card.quoteCount)").font(.system(size: 11)).foregroundStyle(c.muted)
            }
            Text(card.quote.t).font(.serif(16)).foregroundStyle(c.parchment).lineSpacing(3).padding(.top, 8).padding(.bottom, 6)
                .fixedSize(horizontal: false, vertical: true)
            if !card.quote.a.isEmpty {
                Text("— " + card.quote.a).font(.system(size: 12)).foregroundStyle(c.muted).frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(c.track, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.line))
        .overlay(alignment: .leading) { UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 10).fill(c.brass).frame(width: 3) }
        .padding(.top, 4).padding(.bottom, 16)
    }

    @ViewBuilder func extraCredit(_ card: TodayCard) -> some View {
        if let xc = card.extraCredit {
            let done = !inputs.ec.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            VStack(alignment: .leading, spacing: 0) {
                HStack { Eyebrow(text: "Extra credit", color: c.brass); Spacer(); Text("Optional").font(.system(size: 11)).foregroundStyle(c.muted) }
                Text(xc.ref).font(.serif(20)).foregroundStyle(c.brass).padding(.top, 7)
                Text("Pastor’s challenge · one chapter a day through Christmas Eve" + (xc.pass.map { " · pass \($0)" } ?? ""))
                    .font(.system(size: 11)).foregroundStyle(c.muted).padding(.top, 3)
                Text(xc.q).font(.system(size: 14)).foregroundStyle(c.parchment).lineSpacing(2).padding(.top, 11).padding(.bottom, 8)
                    .fixedSize(horizontal: false, vertical: true)
                WriteBox(text: $inputs.ec, minHeight: 64).focused($focused)
                    .onChange(of: inputs.ec) { _, _ in scheduleSave() }
            }
            .padding(.horizontal, 14).padding(.vertical, 13)
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.brass, style: StrokeStyle(lineWidth: 1, dash: done ? [] : [5, 4])))
            .padding(.top, 4).padding(.bottom, 16)
        } else if card.extraCreditLocked {
            Text("Extra credit is for the day you are on — do today’s 1 Timothy chapter before reading ahead.")
                .font(.system(size: 12)).foregroundStyle(c.ghost)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(c.line, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                .padding(.top, 4).padding(.bottom, 16)
        }
    }

    func trackers(_ card: TodayCard) -> some View {
        VStack(spacing: 0) {
            trackerGroup("Yesterday", card.yesterday ?? [], steps: card.steps)
            trackerGroup("Today", card.todayAsks ?? [], steps: nil)
        }
    }
    func trackerGroup(_ head: String, _ asks: [TodayCard.Ask], steps: (day: DayKey, value: Double?)?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(head.uppercased()).font(.system(size: 11)).tracking(1.1).foregroundStyle(c.ghost)
                Spacer(minLength: 10)
                FlowRow(spacing: 16) {
                    ForEach(asks) { a in
                        TrackerToggle(tracker: a.tracker, value: inputs.picks[a.id] ?? nil) { v in
                            inputs.picks[a.id] = .some(v); saveNow(day: viewDay)
                        }
                    }
                }
            }
            if let s = steps { stepsLine(s) }
        }
        .padding(.top, 12).padding(.bottom, 14).padding(.horizontal, 2)
        .overlay(alignment: .top) { Rectangle().fill(c.line).frame(height: 1) }
    }

    func stepsLine(_ s: (day: DayKey, value: Double?)) -> some View {
        let stats = store.log.stepStats
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Text("Steps").font(.system(size: 12)).foregroundStyle(c.muted)
                TextField("0", text: $inputs.steps)
                    .keyboardType(.numberPad).focused($focused).accessibilityIdentifier("steps")
                    .font(.system(size: 13).monospacedDigit()).foregroundStyle(c.parchment)
                    .padding(.horizontal, 12).padding(.vertical, 5).frame(width: 104)
                    .background(c.ink, in: Capsule()).overlay(Capsule().stroke(c.line))
                    .onChange(of: inputs.steps) { _, _ in scheduleSave() }
                LinkButton(title: healthBusy ? "Checking…" : "From Health") { fromHealth(s.day) }
            }
            Text(store.log.stepNeedText(stats)).font(.system(size: 12)).foregroundStyle(c.muted.opacity(0.8))
        }
    }

    func footer(_ card: TodayCard) -> some View {
        HStack {
            Text(store.status.isEmpty ? (card.answered > 0 ? "Saved on this device" : "Nothing written yet") : store.status)
                .font(.system(size: 12)).foregroundStyle(store.statusIsError ? c.rust : c.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            let full = card.answered == 3
            Text("\(card.answered)/3").font(.system(size: 11, weight: full ? .semibold : .regular).monospacedDigit())
                .foregroundStyle(full ? c.ink : c.muted).padding(.horizontal, 9).padding(.vertical, 3)
                .background(full ? c.brass : .clear, in: Capsule()).overlay(Capsule().stroke(full ? c.brass : c.line))
        }
        .padding(.top, 16)
    }

    @ViewBuilder var recent: some View {
        let lg = store.log
        let ds = lg.loggedDays.filter { !lg.isStale(lg.entry($0)) }.reversed().prefix(14)
        if !ds.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                SectionHead(left: "Recent")
                ForEach(Array(ds), id: \.self) { n in
                    let e = lg.entry(n), d = Log.str(e, "date"), full = lg.isComplete(e)
                    Button { go(n) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(d.isEmpty ? "Day \(n)" : lg.days.short(d)).font(.system(size: 12)).foregroundStyle(c.muted).frame(width: 52, alignment: .leading)
                            Text(ReadingPlan.day(n).read).font(.system(size: 13)).foregroundStyle(c.brass).lineLimit(1)
                            Spacer()
                            Text(full ? "3/3" : "\(lg.answered(e))/3").font(.system(size: 11)).foregroundStyle(full ? c.brass : c.muted)
                        }
                        .padding(.vertical, 11).padding(.horizontal, 2).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .hairline(c)
                }
            }
            .padding(.top, 8)
        }
    }

    var actions: some View {
        let lg = store.log
        return VStack(spacing: 8) {
            HStack(spacing: 8) {
                OutlineButton(title: "Share notes") { sharing = SharedFile(name: "bible-log.md", text: lg.markdown()) }
                OutlineButton(title: "Share backup") { sharing = SharedFile(name: "bible-log-backup.json", text: lg.state.text(pretty: true)) }
            }
            HStack(spacing: 8) {
                OutlineButton(title: "Restore backup", quiet: true) { importing = true }
                OutlineButton(title: store.syncOn ? "Sync now" : "Set up sync", quiet: true) {
                    if store.syncOn { Task { await store.sync(manual: true) } } else { syncOpen = true }
                }
            }
        }
        .padding(.top, 20)
    }

    var footText: String {
        store.cloudNote + (store.githubToken != nil ? " Also syncing with the website." : "") + " Backups still work anytime."
    }

    // MARK: behaviour

    func binding(_ kp: WritableKeyPath<DayInputs, [String: String]>, _ id: String) -> Binding<String> {
        Binding(get: { inputs[keyPath: kp][id] ?? "" },
                set: { inputs[keyPath: kp][id] = $0; scheduleSave() })
    }

    func go(_ day: Int) {
        store.setStatus("")
        viewDay = max(1, min(ReadingPlan.count, day))
    }

    func reload(force: Bool) {
        if !force && (focused || dirty) { return }
        let card = self.card
        if force || loadedDay == card.day {
            inputs = DayInputs(card)
            loadedDay = card.day
        }
    }

    func scheduleSave() {
        dirty = true
        store.setStatus("Saving…")
        saveTask?.cancel()
        let day = viewDay
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            saveNow(day: day)
        }
    }

    func saveNow(day: Int) {
        saveTask?.cancel(); saveTask = nil
        guard loadedDay == day, day >= 1 else { return }
        let card = store.log.todayCard(day)
        let draft = inputs.draft(for: card)
        store.edit { $0.saveDay(day, draft) }
        dirty = false
    }

    func fromHealth(_ day: DayKey) {
        healthBusy = true
        Task {
            defer { healthBusy = false }
            do {
                let n = try await Health.steps(on: store.log.days.date(day), calendar: store.log.days.calendar)
                if n <= 0 {
                    store.setStatus("Health shows no steps that day — if that's wrong, allow Reading Log in Settings → Health → Data Access.", error: true)
                    return
                }
                inputs.steps = Fmt.n(n)
                saveNow(day: viewDay)
            } catch {
                store.setStatus("Health: \(error.localizedDescription)", error: true)
            }
        }
    }

    func restore(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let j = try JSON.parse(Data(contentsOf: url))
            var failed: Error?
            store.edit { lg in do { try lg.importBackup(j) } catch { failed = error } }
            if let f = failed { throw f }
            reload(force: true)
        } catch {
            store.setStatus("That file didn't look like a backup from this app.", error: true)
        }
    }
}

/// Lays out tracker toggles left to right, wrapping when they don't fit (like flex-wrap).
struct FlowRow: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, row: CGFloat = 0, widest: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > 0 && x + z.width > w { y += row + 8; x = 0; row = 0 }
            x += z.width + spacing; row = max(row, z.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: min(w, widest), height: y + row)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, row: CGFloat = 0
        for s in subviews {
            let z = s.sizeThatFits(.unspecified)
            if x > b.minX && x + z.width > b.maxX { y += row + 8; x = b.minX; row = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(z))
            x += z.width + spacing; row = max(row, z.height)
        }
    }
}

/// A file handed to the share sheet (Save to Files, AirDrop, Mail…).
struct SharedFile: Identifiable {
    let id = UUID()
    let url: URL
    init(name: String, text: String) {
        url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: [url], applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
