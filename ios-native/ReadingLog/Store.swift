import Foundation
import Observation
import SwiftUI
import ReadingLogCore

/// Shared storage a future widget can read: the App Group container when the entitlement is
/// present, otherwise the app's own Application Support folder.
enum Shared {
    static let group = "group.com.matthewsb419.readinglog"
    static var folder: URL {
        if let g = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) { return g }
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    static var defaults: UserDefaults { UserDefaults(suiteName: group) ?? .standard }
}

/// The app's single source of truth: the log for whoever owns this iCloud account, saved on the
/// phone, and synced to their iCloud (and the website, if they've added a GitHub token).
@MainActor @Observable
final class Store {
    var log = Log()
    var status = ""
    var statusIsError = false
    var cloudState: Cloud.State = .unknown
    private(set) var profileID = ""
    private(set) var ready = false
    private var syncing = false
    private var pushTask: Task<Void, Never>?
    private let cloud = Cloud()
    private let github = GitHubSync()
    private var githubSHA: String?

    // MARK: profile + storage

    private var profileKey: String { profileID.isEmpty ? "local" : profileID }
    private func fileURL(_ key: String) -> URL { Shared.folder.appendingPathComponent("log.\(key).json") }

    var githubToken: String? {
        get { Keychain.get(profileKey) }
        set { Keychain.set(profileKey, newValue) }
    }
    var syncOn: Bool { cloudState == .available || githubToken != nil }

    /// After Face ID: find out whose phone this is, open their log, and sync.
    func start() async {
        let last = Shared.defaults.string(forKey: "profile") ?? ""
        let (state, id) = await cloud.account()
        cloudState = state
        switch state {
        case .available: profileID = id ?? last
        case .noAccount, .restricted: profileID = ""
        default: profileID = last   // iCloud is slow to answer: stay on whoever used this phone last
        }
        Shared.defaults.set(profileID, forKey: "profile")
        // entries written before iCloud answered belong to whoever unlocked the phone: fold them in
        let orphan = fileURL("local"), mine = fileURL(profileKey)
        if !profileID.isEmpty, FileManager.default.fileExists(atPath: orphan.path), !FileManager.default.fileExists(atPath: mine.path) {
            try? FileManager.default.moveItem(at: orphan, to: mine)
        }
        load()
        ready = true
        await sync(manual: false)
    }

    func load() {
        tick()
        if let data = try? Data(contentsOf: fileURL(profileKey)), let j = try? JSON.parse(data) {
            log.state = j
        } else {
            log.state = .object([:])
        }
        log.normalize()
    }

    /// Keep "today" current — the log is read against the clock.
    func tick() { log.days = Days() }

    /// Save on the phone, then sync a moment later.
    func save(quiet: Bool = false) {
        do {
            try log.state.encoded().write(to: fileURL(profileKey), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            if !quiet { setStatus("Saved on this device") }
        } catch {
            setStatus("Couldn't save — \(error.localizedDescription). Export your notes now.", error: true)
        }
        schedulePush()
    }

    func setStatus(_ s: String, error: Bool = false) { status = s; statusIsError = error }

    /// Apply an edit with the clock fresh, then save.
    func edit(_ change: (inout Log) -> Void) {
        tick()
        change(&log)
        save()
    }

    // MARK: sync

    private func schedulePush() {
        guard syncOn else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await self?.sync(manual: false)
        }
    }

    func flushPush() {
        guard pushTask != nil else { return }
        pushTask?.cancel(); pushTask = nil
        Task { await sync(manual: false) }
    }

    func sync(manual: Bool) async {
        guard !syncing else { return }
        syncing = true
        defer { syncing = false }
        if manual { setStatus("Syncing…") }
        if cloudState == .available {
            do {
                for _ in 0..<4 {
                    let text = try await cloud.pull()
                    let remote = text.flatMap { try? JSON.parse($0) }
                    if let r = remote { tick(); if log.mergeRemote(r) { save(quiet: true) } }
                    if remote == log.state { break }
                    if try await !cloud.push(log.state.text()) { break }   // a conflict loops round to merge again
                }
                pushTask?.cancel()
                setStatus("Synced with iCloud")
            } catch {
                setStatus("iCloud: \(Cloud.describe(error))", error: true)
            }
        }
        if let token = githubToken { await githubSync(token, manual: manual) }
    }

    private func githubSync(_ token: String, manual: Bool) async {
        do {
            for _ in 0..<4 {
                let (text, sha) = try await github.pull(token)
                githubSHA = sha
                let remote = text.flatMap { try? JSON.parse($0) }
                if let r = remote { tick(); if log.mergeRemote(r) { save(quiet: true) } }
                if remote == log.state { break }
                if try await github.push(token, text: log.state.text(pretty: false), sha: githubSHA) { break }
            }
            pushTask?.cancel()
            setStatus(cloudState == .available ? "Synced with iCloud and the website" : "Synced")
        } catch {
            setStatus("Sync: \(error.localizedDescription)", error: true)
        }
    }

    var cloudNote: String {
        switch cloudState {
        case .available: return "Saved privately in your iCloud account — only you can read it, and your other Apple devices on the same iCloud pick it up."
        case .noAccount: return "Saved on this iPhone only. Sign in to iCloud in Settings to back up your log and keep it private to you."
        case .restricted: return "iCloud is restricted on this device, so the log is saved on this iPhone only."
        default: return "iCloud isn’t answering right now; your log is saved on this iPhone and will sync when it’s back."
        }
    }

    /// Days until the GitHub token expires, when one is saved and it's within three weeks.
    var tokenWarning: String? {
        guard githubToken != nil else { return nil }
        let left = log.days.between(log.days.today, GitHubSync.tokenExpires)
        if left > 21 { return nil }
        let when = log.days.short(GitHubSync.tokenExpires)
        return left < 0 ? "Sync token expired \(when) — website sync is paused. Open Sync settings to paste a new one."
                        : "Sync token expires \(when) — \(left) day\(left == 1 ? "" : "s") left."
    }
}
