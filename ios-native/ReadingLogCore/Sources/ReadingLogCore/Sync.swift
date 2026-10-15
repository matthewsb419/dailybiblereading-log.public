import Foundation

extension Log {
    /// Merge another device's copy: per entry, per mark and per quote the most recent edit wins.
    @discardableResult
    public mutating func mergeRemote(_ remote: JSON) -> Bool {
        var changed = false
        if let theirs = remote["entries"]?.object {
            var all = entries
            for (k, t) in theirs {
                let mine = all[k]?.object
                if mine == nil || (t["savedAt"]?.string ?? "") > Log.savedAt(mine) { all[k] = t; changed = true }
            }
            entries = all
        }
        if let rg = remote["goals"]?.array, !rg.isEmpty,
           goals.isEmpty || (remote["goalsSavedAt"]?.string ?? "") > (state["goalsSavedAt"]?.string ?? "") {
            if rg != (state["goals"]?.array ?? []) {
                state["goals"] = .array(rg)
                state["goalsSavedAt"] = remote["goalsSavedAt"]
                changed = true
            }
        }
        if let m = remote["marks"], m.truthy, mergeMarks(m) { changed = true }
        if let q = remote["myQuotes"], q.truthy, mergeMyQuotes(q) { changed = true }
        return changed
    }

    @discardableResult
    public mutating func mergeMyQuotes(_ src: JSON) -> Bool {
        var changed = false
        var list = state["myQuotes"]?.array ?? []
        var byID: [String: Int] = [:]
        for (i, q) in list.enumerated() { if let id = q["id"]?.string, !id.isEmpty { byID[id] = i } }
        for q in src.array ?? [] {
            guard let id = q["id"]?.string, !id.isEmpty else { continue }
            if let i = byID[id] {
                if (q["at"]?.string ?? "") > (list[i]["at"]?.string ?? "") { list[i] = q; changed = true }
            } else { byID[id] = list.count; list.append(q); changed = true }
        }
        state["myQuotes"] = .array(list)
        return changed
    }

    /// "Restore backup": keep whichever copy of each day has more written.
    public mutating func importBackup(_ incoming: JSON) throws {
        guard let theirs = incoming["entries"]?.object else { throw LogError.notABackup }
        var all = entries
        for (k, t) in theirs {
            let mine = all[k]?.object
            if mine == nil || answered(t.object) > answered(mine) { all[k] = t }
        }
        entries = all
        if let m = incoming["marks"], m.truthy { mergeMarks(m) }
        if let q = incoming["myQuotes"], q.truthy { mergeMyQuotes(q) }
    }

    public func markdown() -> String {
        var lines = ["# Bible reading log", ""]
        if !goals.isEmpty {
            lines += ["## Life goals", ""]
            for (i, g) in goals.enumerated() { lines.append("\(i + 1). \(g)") }
            lines.append("")
        }
        let mq = myQuotes
        if !mq.isEmpty {
            lines += ["## My quotes", ""]
            for q in mq { lines += ["> " + q.t.replacingOccurrences(of: "\n", with: "\n> ") + (q.a.isEmpty ? "" : "\n> — " + q.a), ""] }
        }
        for (n, e) in orderedEntries {
            let p = ReadingPlan.day(n), d = Log.str(e, "date")
            lines += ["## Day \(n) — \(p.read)" + (d.isEmpty ? "" : " — " + days.pretty(d)), ""]
            for q in questions {
                let a = Log.str(e, q.id).trimmingCharacters(in: .whitespacesAndNewlines)
                if !a.isEmpty { lines += ["**\(q.prompt)**", "", a, ""] }
            }
            if let xs = ecStored(e) {
                lines += ["**Extra credit — \(xs.ref)**", "", xs.q, "", Log.str(e, "ec").trimmingCharacters(in: .whitespacesAndNewlines), ""]
            }
        }
        return lines.joined(separator: "\n")
    }
}

public enum LogError: LocalizedError {
    case notABackup
    public var errorDescription: String? { "That file didn't look like a backup from this app." }
}
