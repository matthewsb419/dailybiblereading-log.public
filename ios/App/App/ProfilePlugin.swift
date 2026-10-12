import Foundation
import UIKit
import Capacitor
import CloudKit
import LocalAuthentication
import HealthKit

/// The app's private-profile layer, called from index.html as `Profile`:
/// Face ID (or the phone passcode) to open the app, and the person's log kept in
/// their own iCloud private database, encrypted so only their Apple ID can read it.
@objc(ProfilePlugin)
public class ProfilePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "ProfilePlugin"
    public let jsName = "Profile"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "unlock", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "account", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pull", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "push", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "share", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "steps", returnType: CAPPluginReturnPromise)
    ]

    private lazy var container = CKContainer(identifier: "iCloud.com.matthewsb419.readinglog")
    private var database: CKDatabase { container.privateCloudDatabase }
    // the whole log is one small JSON document, so one record per person is enough
    private let recordID = CKRecord.ID(recordName: "log")
    private let recordType = "Log"
    private let lock = NSLock()
    private var _lastRecord: CKRecord?
    private var lastRecord: CKRecord? {
        get { lock.lock(); defer { lock.unlock() }; return _lastRecord }
        set { lock.lock(); _lastRecord = newValue; lock.unlock() }
    }

    // MARK: Face ID

    @objc func unlock(_ call: CAPPluginCall) {
        #if targetEnvironment(simulator)
        // no Face ID to fumble with in the simulator; real iPhones always ask
        call.resolve(["ok": true, "protected": false])
        #else
        let context = LAContext()
        var error: NSError?
        // biometrics with the passcode as fallback; a phone with no passcode at all can't be locked
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            call.resolve(["ok": true, "protected": false])
            return
        }
        let reason = call.getString("reason") ?? "Unlock your reading log"
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, err in
            if ok {
                call.resolve(["ok": true, "protected": true])
            } else {
                call.reject(err?.localizedDescription ?? "Not unlocked")
            }
        }
        #endif
    }

    // MARK: iCloud profile

    @objc func account(_ call: CAPPluginCall) {
        container.accountStatus { [weak self] status, err in
            guard let self = self else { return }
            if let err = err {
                call.resolve(["status": "error", "message": err.localizedDescription])
                return
            }
            let name: String
            switch status {
            case .available: name = "available"
            case .noAccount: name = "noAccount"
            case .restricted: name = "restricted"
            case .temporarilyUnavailable: name = "temporarilyUnavailable"
            default: name = "couldNotDetermine"
            }
            guard status == .available else {
                call.resolve(["status": name])
                return
            }
            // the record name is stable per Apple ID and per app, and reveals nothing about the person
            self.container.fetchUserRecordID { id, err in
                if let id = id {
                    call.resolve(["status": name, "userId": id.recordName])
                } else {
                    call.resolve(["status": "error", "message": err?.localizedDescription ?? "No iCloud user"])
                }
            }
        }
    }

    @objc func pull(_ call: CAPPluginCall) {
        database.fetch(withRecordID: recordID) { [weak self] record, err in
            guard let self = self else { return }
            if let ckErr = err as? CKError, ckErr.code == .unknownItem {
                self.lastRecord = nil
                call.resolve(["data": NSNull()])
                return
            }
            if let err = err {
                call.reject(Self.describe(err))
                return
            }
            guard let record = record else {
                call.resolve(["data": NSNull()])
                return
            }
            self.lastRecord = record
            let data = record.encryptedValues["data"] as? String
            call.resolve(["data": data ?? NSNull()])
        }
    }

    @objc func push(_ call: CAPPluginCall) {
        guard let data = call.getString("data") else {
            call.reject("Nothing to save")
            return
        }
        let record = lastRecord ?? CKRecord(recordType: recordType, recordID: recordID)
        record.encryptedValues["data"] = data

        let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
        // refuse to overwrite a newer copy from another device; the page merges and tries again
        op.savePolicy = .ifServerRecordUnchanged
        op.qualityOfService = .userInitiated
        var answered = false   // the per-record and whole-operation callbacks run on one serial queue
        op.perRecordSaveBlock = { [weak self] _, result in
            guard let self = self else { return }
            answered = true
            switch result {
            case .success(let saved):
                self.lastRecord = saved
                call.resolve(["conflict": false])
            case .failure(let err):
                if let ckErr = err as? CKError, ckErr.code == .serverRecordChanged {
                    self.lastRecord = ckErr.serverRecord
                    call.resolve(["conflict": true])
                } else {
                    call.reject(Self.describe(err))
                }
            }
        }
        op.modifyRecordsResultBlock = { result in
            guard !answered else { return }
            switch result {
            case .success: call.resolve(["conflict": false])
            case .failure(let err): call.reject(Self.describe(err))
            }
        }
        database.add(op)
    }

    private static func describe(_ err: Error) -> String {
        guard let ckErr = err as? CKError else { return err.localizedDescription }
        switch ckErr.code {
        case .networkUnavailable, .networkFailure: return "offline — will sync when you're back online"
        case .notAuthenticated: return "sign in to iCloud in Settings to sync"
        case .quotaExceeded: return "your iCloud storage is full"
        default: return ckErr.localizedDescription
        }
    }

    // MARK: Steps from Apple Health

    private lazy var health = HKHealthStore()

    /// Total steps for one calendar day ("YYYY-MM-DD", local time), read-only. Health merges
    /// iPhone and Apple Watch counts so nothing is counted twice.
    @objc func steps(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            call.reject("Apple Health isn't available on this device")
            return
        }
        let fmt = DateFormatter()
        fmt.calendar = Calendar(identifier: .gregorian)
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.dateFormat = "yyyy-MM-dd"
        guard let dayString = call.getString("date"), let day = fmt.date(from: dayString),
              let next = Calendar.current.date(byAdding: .day, value: 1, to: day) else {
            call.reject("Bad date")
            return
        }
        health.requestAuthorization(toShare: nil, read: [type]) { [weak self] _, err in
            guard let self = self else { return }
            if let err = err {
                call.reject(err.localizedDescription)
                return
            }
            let range = HKQuery.predicateForSamples(withStart: day, end: next, options: .strictStartDate)
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: range, options: .cumulativeSum) { _, stats, err in
                if let err = err as? HKError, err.code == .errorNoData {
                    call.resolve(["steps": 0])
                    return
                }
                if let err = err {
                    call.reject(err.localizedDescription)
                    return
                }
                let n = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                call.resolve(["steps": Int(n.rounded())])
            }
            self.health.execute(query)
        }
    }

    // MARK: Export

    /// Backups and notes go out through the share sheet (Save to Files, AirDrop, Mail…).
    @objc func share(_ call: CAPPluginCall) {
        let text = call.getString("text") ?? ""
        let filename = call.getString("filename") ?? "bible-log.txt"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            call.reject("Couldn't write \(filename)")
            return
        }
        DispatchQueue.main.async { [weak self] in
            guard let vc = self?.bridge?.viewController else {
                call.reject("No window to share from")
                return
            }
            let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            sheet.popoverPresentationController?.sourceView = vc.view
            sheet.popoverPresentationController?.sourceRect = CGRect(x: vc.view.bounds.midX, y: vc.view.bounds.maxY - 80, width: 1, height: 1)
            sheet.completionWithItemsHandler = { _, completed, _, _ in
                try? FileManager.default.removeItem(at: url)
                call.resolve(["completed": completed])
            }
            vc.present(sheet, animated: true)
        }
    }
}

/// Registers the in-app plugin with Capacitor's bridge.
class AppViewController: CAPBridgeViewController {
    override func capacitorDidLoad() {
        bridge?.registerPluginInstance(ProfilePlugin())
    }
}
