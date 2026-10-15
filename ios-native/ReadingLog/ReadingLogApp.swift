import SwiftUI
import ReadingLogCore

@main
struct ReadingLogApp: App {
    @State private var store = Store()
    @State private var keg = KegRunner()
    @AppStorage("themePick", store: Shared.defaults) private var themePick = 0

    var body: some Scene {
        WindowGroup {
            let palette = Palette.at(themePick)
            RootView()
                .environment(store)
                .environment(keg)
                .environment(\.palette, palette)
                .preferredColorScheme(palette.isLight ? .light : .dark)
                .tint(palette.brass)
        }
    }
}

/// Face ID first; the log only appears once unlocked, and the app locks again after a minute away.
struct RootView: View {
    @Environment(Store.self) private var store
    @Environment(\.palette) private var c
    @Environment(\.scenePhase) private var phase
    @State private var unlocked = false
    @State private var asking = false
    @State private var failed = false
    @State private var awayAt: Date?

    var body: some View {
        ZStack {
            c.ink.ignoresSafeArea()
            if unlocked && store.ready {
                MainView()
            } else {
                lockScreen
            }
            if phase != .active && !asking { c.ink.ignoresSafeArea() }   // nothing readable in the app switcher
        }
        .task { await unlock() }
        .onChange(of: phase) { _, p in
            switch p {
            case .background:
                awayAt = Date()
                store.flushPush()
            case .active:
                guard unlocked else { return }
                if let t = awayAt, Date().timeIntervalSince(t) > 60 {
                    unlocked = false
                    Task { await unlock() }
                } else {
                    store.tick()
                    Task { await store.sync(manual: false) }   // pick up anything saved on another device
                }
                awayAt = nil
            default: break
            }
        }
    }

    var lockScreen: some View {
        VStack(spacing: 0) {
            Eyebrow(text: "Private").padding(.bottom, 4)
            Text("Reading Log").font(.serif(30).weight(.semibold)).foregroundStyle(c.parchment).padding(.bottom, 22)
            OutlineButton(title: "Unlock") { Task { await unlock() } }.frame(maxWidth: 300)
            Text(failed ? "Still locked." : " ").font(.system(size: 12)).foregroundStyle(c.rust).padding(.top, 10)
        }
        .padding(18)
    }

    func unlock() async {
        guard !asking else { return }
        asking = true
        let ok = await Lock.unlock()
        asking = false
        failed = !ok
        guard ok else { return }
        unlocked = true
        if !store.ready { await store.start() } else { store.tick(); await store.sync(manual: false) }
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-snapshot") { Snapshot.renderAll(store: store, palette: c) }
        #endif
    }
}

enum Page: String, CaseIterable { case today, record, goals, quotes, next, plan }

struct MainView: View {
    @Environment(Store.self) private var store
    @Environment(KegRunner.self) private var keg
    @Environment(\.palette) private var c
    @State private var page: Page = .today
    @State private var viewDay = 0
    @State private var themes = false
    @State private var tokenBannerHidden = false

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header.id("top")
                    nav
                    switch page {
                    case .today: TodayView(viewDay: $viewDay)
                    case .record: RecordView(page: $page)
                    case .plan: PlanView(page: $page)
                    case .goals: GoalsView()
                    case .quotes: QuotesView()
                    case .next: NextView()
                    }
                }
                .padding(.horizontal, 18).padding(.top, 22).padding(.bottom, 48)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: page) { _, _ in proxy.scrollTo("top", anchor: .top) }
        }
        .background(c.ink)
        .safeAreaInset(edge: .bottom) {
            if let w = store.tokenWarning, !tokenBannerHidden {
                HStack {
                    Text(w).font(.system(size: 13)).foregroundStyle(c.parchment).multilineTextAlignment(.center).frame(maxWidth: .infinity)
                    Button { tokenBannerHidden = true } label: { Image(systemName: "xmark").foregroundStyle(c.parchment) }
                }
                .padding(.horizontal, 14).padding(.vertical, 10).background(c.rust)
            }
        }
        .sheet(isPresented: $themes) { ThemePicker() }
        .onAppear { if viewDay == 0 { viewDay = store.log.currentDay } }
        .onChange(of: store.log.days.today) { _, _ in if page == .today { viewDay = store.log.currentDay } }
    }

    var header: some View {
        HStack(alignment: .bottom, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Reading log")
                Text(ReadingPlan.day(max(1, viewDay)).book).font(.serif(30).weight(.semibold)).foregroundStyle(c.parchment)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer()
            Button { themes = true } label: {
                Image(systemName: "paintpalette").font(.system(size: 15)).foregroundStyle(c.muted)
            }
            .accessibilityLabel("Try a look")
            .padding(.bottom, 6)
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(max(1, viewDay))").font(.serif(28)).foregroundStyle(c.brass)
                Text("of \(ReadingPlan.count)").font(.system(size: 11)).foregroundStyle(c.muted)
            }
        }
        .padding(.bottom, 16)
    }

    var nav: some View {
        let tabs: [(Page, String)] = [(.today, "Today"), (.record, "Record"), (.goals, "Goals"), (.quotes, "Quotes"), (.next, "Next")]
        return FlowRow(spacing: 4) {
            ForEach(tabs, id: \.0) { p, title in
                let on = page == p || (p == .record && page == .plan)
                Button {
                    if keg.finished { keg.reset() }   // the finished-session card doesn't follow you around
                    store.setStatus("")
                    page = p
                } label: {
                    Text(title.uppercased()).font(.system(size: 13)).tracking(0.8)
                        .foregroundStyle(on ? c.brass : c.muted)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .overlay(alignment: .bottom) { Rectangle().fill(on ? c.brass : .clear).frame(height: 2) }
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .hairline(c)
        .padding(.bottom, 16)
    }
}
