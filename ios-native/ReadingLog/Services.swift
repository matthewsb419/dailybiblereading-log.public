import Foundation
import CloudKit
import HealthKit
import LocalAuthentication
import Security

/// iCloud: each person's log is one encrypted record in their own private CloudKit database,
/// shared with the wrapper app (same container, same record), so only their Apple ID can read it.
final class Cloud: @unchecked Sendable {
    enum State: String { case unknown, available, noAccount, restricted, temporarilyUnavailable, couldNotDetermine, error }

    private lazy var container = CKContainer(identifier: "iCloud.com.matthewsb419.readinglog")
    private var db: CKDatabase { container.privateCloudDatabase }
    private let recordID = CKRecord.ID(recordName: "log")
    private var lastRecord: CKRecord?

    /// The account's state and, when signed in, a stable anonymous ID for this Apple ID.
    func account() async -> (State, String?) {
        do {
            let status = try await container.accountStatus()
            switch status {
            case .available:
                let id = try await container.userRecordID()
                return (.available, id.recordName)
            case .noAccount: return (.noAccount, nil)
            case .restricted: return (.restricted, nil)
            case .temporarilyUnavailable: return (.temporarilyUnavailable, nil)
            default: return (.couldNotDetermine, nil)
            }
        } catch {
            return (.error, nil)
        }
    }

    func pull() async throws -> String? {
        do {
            let record = try await db.record(for: recordID)
            lastRecord = record
            return record.encryptedValues["data"] as? String
        } catch let e as CKError where e.code == .unknownItem {
            lastRecord = nil
            return nil
        }
    }

    /// Saves the log; returns true when another device saved first (pull, merge, try again).
    func push(_ text: String) async throws -> Bool {
        let record = lastRecord ?? CKRecord(recordType: "Log", recordID: recordID)
        record.encryptedValues["data"] = text
        let (saved, _) = try await db.modifyRecords(saving: [record], deleting: [], savePolicy: .ifServerRecordUnchanged, atomically: true)
        switch saved[recordID] {
        case .success(let r): lastRecord = r; return false
        case .failure(let e as CKError) where e.code == .serverRecordChanged:
            lastRecord = e.serverRecord
            return true
        case .failure(let e): throw e
        case nil: return false
        }
    }

    static func describe(_ error: Error) -> String {
        guard let e = error as? CKError else { return error.localizedDescription }
        switch e.code {
        case .networkUnavailable, .networkFailure: return "offline — will sync when you're back online"
        case .notAuthenticated: return "sign in to iCloud in Settings to sync"
        case .quotaExceeded: return "your iCloud storage is full"
        default: return e.localizedDescription
        }
    }
}

/// Optional sync with the website's private GitHub data repo, exactly as the website does it.
struct GitHubSync {
    static let repo = "matthewsb419/dailybiblereading-data"
    static let url = URL(string: "https://api.github.com/repos/\(repo)/contents/data.json")!
    static let tokenExpires = "2026-12-04"

    struct Failure: LocalizedError { let errorDescription: String? }

    private func request(_ token: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var r = URLRequest(url: Self.url)
        r.httpMethod = method
        r.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        r.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        r.cachePolicy = .reloadIgnoringLocalCacheData
        r.httpBody = body
        return r
    }

    /// The repo's copy (nil if the file doesn't exist yet) and its version tag.
    func pull(_ token: String) async throws -> (text: String?, sha: String?) {
        let (data, resp) = try await URLSession.shared.data(for: request(token))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        switch code {
        case 404: return (nil, nil)
        case 401: throw Failure(errorDescription: "GitHub says the token is invalid — re-copy the exact github_pat value and paste it again")
        case 403: throw Failure(errorDescription: "token lacks permission — set Contents to Read and write on the data repo")
        case 200..<300: break
        default: throw Failure(errorDescription: "pull failed (\(code))")
        }
        let j = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let b64 = (j["content"] as? String ?? "").replacingOccurrences(of: "\n", with: "")
        let text = Data(base64Encoded: b64).map { String(decoding: $0, as: UTF8.self) }
        return (text, j["sha"] as? String)
    }

    /// Returns false when the repo changed underneath (pull and try again).
    func push(_ token: String, text: String, sha: String?) async throws -> Bool {
        var body: [String: Any] = ["message": "sync \(ISO8601DateFormatter().string(from: Date()))",
                                   "content": Data(text.utf8).base64EncodedString()]
        if let sha = sha { body["sha"] = sha }
        let (_, resp) = try await URLSession.shared.data(for: request(token, method: "PUT", body: try JSONSerialization.data(withJSONObject: body)))
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 409 || code == 422 { return false }
        if code == 404 || code == 403 { throw Failure(errorDescription: "token can't write the data repo — grant it access to \(Self.repo) with Contents read and write") }
        if !(200..<300).contains(code) { throw Failure(errorDescription: "push failed (\(code))") }
        return true
    }
}

/// Face ID, or the phone passcode as a fallback.
enum Lock {
    static func unlock() async -> Bool {
        #if targetEnvironment(simulator)
        return true   // no Face ID to fumble with in the simulator; real iPhones always ask
        #else
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock your reading log")) ?? false
        #endif
    }
}

/// Read-only step counts from Apple Health (iPhone and Watch merged, nothing counted twice).
enum Health {
    private static let store = HKHealthStore()

    static func steps(on day: Date, calendar: Calendar) async throws -> Double {
        guard HKHealthStore.isHealthDataAvailable(), let type = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw GitHubSync.Failure(errorDescription: "Apple Health isn't available on this device")
        }
        try await store.requestAuthorization(toShare: [], read: [type])
        let start = calendar.startOfDay(for: day), end = calendar.date(byAdding: .day, value: 1, to: start)!
        let range = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: range, options: .cumulativeSum) { _, stats, err in
                if let e = err as? HKError, e.code == .errorNoData { cont.resume(returning: 0); return }
                if let err = err { cont.resume(throwing: err); return }
                cont.resume(returning: stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0)
            }
            store.execute(q)
        }
    }
}

/// The GitHub token lives in the Keychain, one per profile.
enum Keychain {
    static func get(_ account: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ReadingLog.github",
                                kSecAttrAccount as String: account, kSecReturnData as String: true]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }
    static func set(_ account: String, _ value: String?) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ReadingLog.github",
                                kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        guard let v = value, !v.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(v.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(add as CFDictionary, nil)
    }
}
