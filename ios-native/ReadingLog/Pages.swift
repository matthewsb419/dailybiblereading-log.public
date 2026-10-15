import SwiftUI
import ReadingLogCore

struct GoalsView: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var c
    @State private var editing = false
    @State private var text = ""

    var body: some View {
        let lg = store.log, gl = lg.goals, todayGi = gl.isEmpty ? -1 : lg.goalIndex(lg.days.today, gl.count)
        VStack(alignment: .leading, spacing: 0) {
            Card {
                SectionHead(left: "Life goals", right: gl.isEmpty ? "" : "\(gl.count) goals")
                if editing {
                    Text("One goal per line. Numbers are added for you.").font(.system(size: 12)).foregroundStyle(c.muted).padding(.bottom, 8)
                    WriteBox(text: $text, minHeight: 340, size: 14)
                    HStack(spacing: 14) {
                        PillButton(title: "Save") { store.edit { $0.saveGoals(text) }; editing = false }
                        LinkButton(title: "Cancel") { editing = false }
                    }
                    .padding(.top, 12)
                } else {
                    if gl.isEmpty {
                        Note(text: "No goals yet. They live in your data, not in the app, so add them here once and they sync to your other devices.")
                    } else {
                        ForEach(Array(gl.enumerated()), id: \.offset) { i, g in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("\(i + 1).").font(.system(size: 14).monospacedDigit()).foregroundStyle(c.muted).frame(width: 22, alignment: .trailing)
                                Text(g).font(.system(size: 14)).foregroundStyle(i == todayGi ? c.brass : c.parchment)
                                    + Text(i == todayGi ? "  TODAY" : "").font(.system(size: 10)).foregroundStyle(c.brass)
                            }
                            .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).hairline(c)
                        }
                    }
                    LinkButton(title: gl.isEmpty ? "Add goals" : "Edit goals") { text = gl.joined(separator: "\n"); editing = true }.padding(.top, 12)
                }
            }
            rhythm(lg)
        }
    }

    func rhythm(_ lg: Log) -> some View {
        let gMap = lg.trackerMap("g"), gFirst = Log.first(gMap)
        let grKeys = Set(lg.orderedEntries.compactMap { e -> DayKey? in
            let d = Log.str(e.entry, "date")
            return !d.isEmpty && Log.str(e.entry, "gr") == "yes" && !lg.isStale(e.entry) ? d : nil
        }).sorted()
        func row(_ label: String, _ n: Int, _ el: Int, _ unit: String, _ since: DayKey) -> ARow {
            let pct = el > 0 ? Double(n) / Double(el) * 100 : 0
            return ARow(label: label, detail: "\(n) of \(el) \(unit) · since \(lg.days.short(since))", pct: Fmt.fixed(pct, 0) + "%", on: pct >= Program.monthTarget)
        }
        return Card(top: 8) {
            SectionHead(left: "Rhythm")
            if let f = gFirst { row("G", gMap.values.filter { $0 == .good }.count, lg.days.count(f, lg.days.today, weekday: 1), "Mondays", f) }
            if let f = grKeys.first { row("Read", grKeys.count, lg.days.count(f, lg.days.today), "days", f) }
            Note(text: "G: every Monday, rewrite the goals in my journal and note any achieved — the G toggle appears on Mondays. Read: one goal is picked for each day and shown under the reading questions; tap Mark as read.")
        }
    }
}

struct QuotesView: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var c
    @State private var text = ""
    @State private var by = ""
    @State private var editID: String?
    @State private var armed: String?

    var body: some View {
        let lg = store.log, todayQi = lg.quoteIndex(lg.days.today), mine = lg.myQuotes, builtIn = Content.shared.quotes
        VStack(alignment: .leading, spacing: 0) {
            Card {
                SectionHead(left: "My quotes", right: mine.isEmpty ? "" : "\(mine.count) added")
                Text(editID != nil ? "Fix this quote" : "Add a quote").font(.system(size: 12)).foregroundStyle(c.muted)
                WriteBox(text: $text, minHeight: 96, size: 15).padding(.top, 8)
                TextField("Who said it", text: $by)
                    .font(.system(size: 13)).foregroundStyle(c.parchment)
                    .padding(.horizontal, 10).padding(.vertical, 7).frame(maxWidth: 320)
                    .background(c.ink, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(c.line))
                    .padding(.top, 8).submitLabel(.done).onSubmit(save)
                HStack(spacing: 14) {
                    PillButton(title: editID != nil ? "Save changes" : "Save", disabled: text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, action: save)
                    if editID != nil { LinkButton(title: "Cancel") { editID = nil; text = ""; by = "" } }
                }
                .padding(.top, 10)
                if mine.isEmpty {
                    Note(text: "Nothing added yet. Quotes you save here join the daily shuffle on the Today tab and sync to your other devices.")
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(mine.enumerated()), id: \.offset) { j, q in
                            let isToday = builtIn.count + j == todayQi
                            quoteRow(builtIn.count + j + 1, q, today: isToday) {
                                HStack(spacing: 16) {
                                    LinkButton(title: "Edit") { editID = q.id; text = q.t; by = q.a; armed = nil }
                                    LinkButton(title: armed == q.id ? "Tap again to delete" : "Delete", danger: armed == q.id) {
                                        guard let id = q.id else { return }
                                        if armed != id { armed = id; return }
                                        store.edit { $0.deleteQuote(id: id) }
                                        if editID == id { editID = nil; text = ""; by = "" }
                                        armed = nil
                                    }
                                }
                                .padding(.top, 2)
                            }
                            .opacity(editID == q.id ? 0.5 : 1)
                        }
                    }
                    .padding(.top, 14)
                }
            }
            Card {
                SectionHead(left: "Encouragement", right: "\(builtIn.count) quotes & verses")
                ForEach(Content.shared.quoteCategories, id: \.id) { cat in
                    Eyebrow(text: cat.name).padding(.top, 18)
                    ForEach(Array(builtIn.enumerated()).filter { $0.element.c == cat.id }, id: \.offset) { i, q in
                        quoteRow(i + 1, q, today: i == todayQi) { EmptyView() }
                    }
                }
                Note(text: "One of these, or one of yours, is picked for each day and shown under the reading questions on the Today tab. Every one comes around before any repeats. Scripture is quoted from the ESV.")
            }
        }
    }

    func quoteRow<A: View>(_ n: Int, _ q: Quote, today: Bool, @ViewBuilder actions: () -> A) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").font(.system(size: 13).monospacedDigit()).foregroundStyle(c.muted).frame(width: 34, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(q.t).font(.serif(15)).foregroundStyle(today ? c.brass : c.parchment).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                if !q.a.isEmpty || today {
                    (Text(q.a.isEmpty ? "" : "— " + q.a).foregroundStyle(c.muted) + Text(today ? "  TODAY" : "").font(.system(size: 10)).foregroundStyle(c.brass))
                        .font(.system(size: 12))
                }
                actions()
            }
        }
        .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).hairline(c)
    }

    func save() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.edit { $0.saveQuote(id: editID, text: text, by: by) }
        text = ""; by = ""; editID = nil; armed = nil
    }
}

struct NextView: View {
    @Environment(\.palette) private var c
    var body: some View {
        let list = Content.shared.nextHabits
        VStack(alignment: .leading, spacing: 0) {
            Card {
                SectionHead(left: "Still to come", right: "\(list.count) waiting")
                Note(text: "One at a time. A new one only starts after everything already tracked has held for a stretch — the point is to keep what is here, not to add faster. Nothing on this page is being tracked yet.")
            }
            ForEach(list, id: \.name) { x in
                Card {
                    SectionHead(left: x.name, right: x.tag)
                    (Text(x.when).bold().foregroundStyle(c.parchment) + Text(" · " + x.sum).foregroundStyle(c.muted)).font(.system(size: 12))
                    if !x.stages.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(x.stages.enumerated()), id: \.offset) { i, st in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("\(i + 1).").foregroundStyle(c.brass)
                                    Text(st).foregroundStyle(c.muted)
                                }
                                .font(.system(size: 13))
                            }
                        }
                        .padding(.top, 12)
                    }
                }
            }
        }
    }
}

struct SyncSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var c
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var help = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(store.cloudNote).font(.system(size: 13)).foregroundStyle(c.parchment)
                    Divider().overlay(c.line)
                    Text("Website sync (optional)").font(.system(size: 14, weight: .semibold)).foregroundStyle(c.parchment)
                    Text("Paste a fine-grained GitHub token with Contents read & write on \(GitHubSync.repo). It is stored only on this device, in the Keychain. Only needed to keep the website in step with this app.")
                        .font(.system(size: 13)).foregroundStyle(c.muted)
                    SecureField(store.githubToken != nil ? "Token saved — paste a new one to replace it" : "github_pat_…", text: $token)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .font(.system(size: 14)).padding(10)
                        .background(c.ink, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(c.line))
                    HStack(spacing: 8) {
                        OutlineButton(title: "Save token") {
                            let v = token.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !v.isEmpty else { return }
                            store.githubToken = v
                            dismiss()
                            Task { await store.sync(manual: true) }
                        }
                        if store.githubToken != nil { OutlineButton(title: "Remove token", quiet: true) { store.githubToken = nil; dismiss() } }
                    }
                    OutlineButton(title: help ? "Hide instructions" : "How to make a token", quiet: true) { help.toggle() }
                    if help { instructions }
                }
                .padding(18)
            }
            .background(c.raised)
            .navigationTitle("Sync").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }

    var instructions: some View {
        let steps = [
            "Open github.com/settings/personal-access-tokens/new and sign in if asked.",
            "Token name: bible-log-sync. Expiration: the longest offered — note the date.",
            "Repository access: choose Only select repositories, then pick dailybiblereading-data. It should say “1 repository selected.”",
            "Scroll down — a Repository permissions list appears only after step 3. Set Contents to Read and write. Touch nothing else.",
            "Check the summary above the button: 2 permissions — Contents (read and write), Metadata (read). Metadata adds itself; that is normal.",
            "Generate the token and copy the github_pat_… value right away — GitHub shows it only this once.",
            "Paste it in the box above and press Save token."
        ]
        return VStack(alignment: .leading, spacing: 8) {
            Link("Open GitHub token page", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!).font(.system(size: 13))
            ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                HStack(alignment: .firstTextBaseline, spacing: 6) { Text("\(i + 1).").foregroundStyle(c.brass); Text(s).foregroundStyle(c.muted) }.font(.system(size: 12))
            }
            Text("If the old token expired, delete it on that same GitHub page — nothing in the app breaks; entries just pause syncing until the new token is saved.")
                .font(.system(size: 12)).foregroundStyle(c.muted)
        }
    }
}

struct ThemePicker: View {
    @Environment(\.palette) private var c
    @Environment(\.dismiss) private var dismiss
    @AppStorage("themePick", store: Shared.defaults) private var pick = 0

    var body: some View {
        let themes = Palette.themes
        let groups = themes.reduce(into: [String]()) { if !$0.contains($1.group) { $0.append($1.group) } }
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        var i = pick
                        while i == pick { i = Int.random(in: 0..<themes.count) }
                        pick = i
                    } label: {
                        Text("Pick a rando").font(.system(size: 13)).tracking(0.5).foregroundStyle(c.brass)
                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(c.brass, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                    }
                    .buttonStyle(.plain)
                    ForEach(groups, id: \.self) { g in
                        Eyebrow(text: g).padding(.top, 12)
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                            ForEach(Array(themes.enumerated()).filter { $0.element.group == g }, id: \.offset) { i, t in
                                Button { pick = i } label: {
                                    HStack(spacing: 8) {
                                        HStack(spacing: 3) {
                                            ForEach([t.brass, t.rust, t.parchment], id: \.self) { RoundedRectangle(cornerRadius: 4).fill(Hex.color($0)).frame(width: 12, height: 12) }
                                        }
                                        Text(t.name).font(.system(size: 12)).foregroundStyle(Hex.color(t.parchment))
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 8).padding(.vertical, 9)
                                    .background(Hex.color(t.raised), in: RoundedRectangle(cornerRadius: 7))
                                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(i == pick ? c.brass : Hex.color(t.line), lineWidth: i == pick ? 2 : 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(c.ink)
            .navigationTitle("Try a look").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
