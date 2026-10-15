import Foundation

// The fixed parts of the program, as the website defines them. Long lists (quotes, extra-credit
// questions, themes, the "Next" page) come from Resources/content.json, which is exported from
// index.html by tools/export-content.mjs so the two never drift apart.

public enum Program {
    // plan
    public static let versesPerMinute = 4.0, ceiling = 60.0, minVerses = 20.0
    public static let monthTarget = 80.0, weekTarget = 80.0, gradeFloor = 5, yearGoal = 365

    // extra credit: 1 Timothy, one chapter a day
    public static let ecStart: DayKey = "2026-09-06", ecEnd: DayKey = "2026-12-24", ecCycle = 6

    // steps: walking goal through Valentine's Day
    public static let stepStart: DayKey = "2026-09-13", stepEnd: DayKey = "2027-02-14"
    public static let stepGoal = 1_000_000.0, stepStretch = 2_000_000.0
    public static let stepGrades: [(Double, String)] = [(95, "B+"), (90, "B"), (85, "B−"), (80, "C+"), (75, "C"), (70, "C−"), (65, "D+"), (60, "D"), (55, "D−")]

    // pelvic floor
    public static let kegStart: DayKey = "2026-09-16"
    public static let kegBreak = 10, kegFlickHold = 1, kegFlickRest = 2
    public static let kegWhere = "sitting"

    public static let grades: [(Double, String)] = [(96, "A+"), (93, "A"), (90, "A−"), (87, "B+"), (83, "B"), (80, "B−"),
                                                    (77, "C+"), (73, "C"), (70, "C−"), (67, "D+"), (63, "D"), (60, "D−")]
    public static func grade(_ p: Double) -> String { grades.first { p >= $0.0 }?.1 ?? "F" }
    public static func stepGrade(_ p: Double) -> String { stepGrades.first { p >= $0.0 }?.1 ?? "F" }
}

public struct Question: Sendable, Identifiable {
    public let id: String
    public let prompt: String
}
public let questions: [Question] = [
    .init(id: "god", prompt: "What does this say about who God is?"),
    .init(id: "stood", prompt: "What stood out or confused me?"),
    .init(id: "today", prompt: "What do I do with it today?")
]

/// A yes/no habit asked on the Today card. `shift` is the day the answer describes relative to
/// the entry's date (−1: yesterday). `good` is the answer that counts as a win.
public struct Tracker: Sendable, Identifiable {
    public let id: String
    public let label: String
    public let good: String
    public let shift: Int
    public var start: DayKey? = nil
    public var weekday: Int? = nil
    public var off: String? = nil
    public var hint: String? = nil
    public var bad: String { good == "yes" ? "no" : "yes" }
}
public let trackers: [Tracker] = [
    .init(id: "p", label: "P", good: "no", shift: -1),
    .init(id: "m", label: "M", good: "no", shift: -1),
    .init(id: "j", label: "J", good: "yes", shift: 0),
    .init(id: "h", label: "H", good: "yes", shift: 0, start: "2026-09-17", hint: "Filled out How We Feel this morning"),
    .init(id: "g", label: "G", good: "yes", shift: 0, weekday: 1, hint: "Rewrote my life goals in my journal"),
    .init(id: "mg", label: "MG", good: "yes", shift: -1, weekday: 1, off: "Didn’t meet", hint: "Went to men’s group Monday night")
]
public func tracker(_ id: String) -> Tracker? { trackers.first { $0.id == id } }

/// Numeric fields kept beside the trackers, and the day they describe (steps: yesterday).
public let numericFields: [String: Int] = ["st": -1, "kg": 0]

public struct KegLevel: Sendable, Equatable {
    public let hold: Int, reps: Int, flicks: Int, sets: Int
    public let name: String
}
public let kegLevels: [KegLevel] = [
    .init(hold: 5, reps: 10, flicks: 10, sets: 3, name: "Build"),
    .init(hold: 6, reps: 10, flicks: 10, sets: 3, name: "Build"),
    .init(hold: 7, reps: 10, flicks: 10, sets: 3, name: "Build"),
    .init(hold: 5, reps: 8, flicks: 8, sets: 2, name: "Deload"),
    .init(hold: 7, reps: 10, flicks: 12, sets: 3, name: "Build"),
    .init(hold: 8, reps: 10, flicks: 12, sets: 3, name: "Build"),
    .init(hold: 9, reps: 10, flicks: 12, sets: 3, name: "Build"),
    .init(hold: 6, reps: 8, flicks: 8, sets: 2, name: "Deload"),
    .init(hold: 9, reps: 12, flicks: 15, sets: 3, name: "Build"),
    .init(hold: 10, reps: 12, flicks: 15, sets: 3, name: "Build"),
    .init(hold: 10, reps: 12, flicks: 15, sets: 3, name: "Peak"),
    .init(hold: 7, reps: 8, flicks: 10, sets: 2, name: "Deload")
]

// MARK: content.json

public struct Quote: Codable, Sendable, Equatable {
    public let c: String
    public let a: String
    public let t: String
    public var id: String? = nil
}
public struct QuoteCategory: Codable, Sendable { public let id: String; public let name: String }
public struct Theme: Codable, Sendable, Equatable {
    public let group: String, name: String
    public let ink: String, raised: String, line: String, parchment: String, muted: String, brass: String, rust: String
}
public struct NextHabit: Codable, Sendable {
    public let name: String, when: String, tag: String, sum: String
    public let stages: [String]
}
public struct Content: Codable, Sendable {
    public let quoteCategories: [QuoteCategory]
    public let quotes: [Quote]
    public let extraCredit: [[String]]
    public let themes: [Theme]
    public let nextHabits: [NextHabit]

    public static let shared: Content = {
        let url = Bundle.module.url(forResource: "content", withExtension: "json")!
        return try! JSONDecoder().decode(Content.self, from: Data(contentsOf: url))
    }()

    public func categoryName(_ c: String) -> String {
        c == "mine" ? "My quotes" : (quoteCategories.first { $0.id == c }?.name ?? "")
    }
}

// MARK: the reading plan

public struct PlanDay: Sendable, Equatable, Identifiable {
    public let day: Int
    public let book: String
    public let read: String
    public let verses: Int
    public let min: Int
    public var id: Int { day }
}

public enum ReadingPlan {
    static let books: [String: (chapters: Int, verses: Int)] = [
        "Genesis": (50, 1533), "Exodus": (40, 1213), "Leviticus": (27, 859), "Numbers": (36, 1288),
        "Deuteronomy": (34, 959), "Joshua": (24, 658), "Judges": (21, 618), "Ruth": (4, 85),
        "1 Samuel": (31, 810), "2 Samuel": (24, 695), "1 Kings": (22, 816), "2 Kings": (25, 719),
        "1 Chronicles": (29, 942), "2 Chronicles": (36, 822), "Ezra": (10, 280), "Nehemiah": (13, 406),
        "Esther": (10, 167), "Job": (42, 1070), "Psalms": (150, 2461), "Proverbs": (31, 915),
        "Ecclesiastes": (12, 222), "Song of Songs": (8, 117), "Isaiah": (66, 1292), "Jeremiah": (52, 1364),
        "Lamentations": (5, 154), "Ezekiel": (48, 1273), "Daniel": (12, 357), "Hosea": (14, 197),
        "Joel": (3, 73), "Amos": (9, 146), "Obadiah": (1, 21), "Jonah": (4, 48), "Micah": (7, 105),
        "Nahum": (3, 47), "Habakkuk": (3, 56), "Zephaniah": (3, 53), "Haggai": (2, 38),
        "Zechariah": (14, 211), "Malachi": (4, 55), "Matthew": (28, 1071), "Mark": (16, 678),
        "Luke": (24, 1151), "John": (21, 879), "Acts": (28, 1007), "Romans": (16, 433),
        "1 Corinthians": (16, 437), "2 Corinthians": (13, 257), "Galatians": (6, 149),
        "Ephesians": (6, 155), "Philippians": (4, 104), "Colossians": (4, 95),
        "1 Thessalonians": (5, 89), "2 Thessalonians": (3, 47), "1 Timothy": (6, 113),
        "2 Timothy": (4, 83), "Titus": (3, 46), "Philemon": (1, 25), "Hebrews": (13, 303),
        "James": (5, 108), "1 Peter": (5, 105), "2 Peter": (3, 61), "1 John": (5, 105),
        "2 John": (1, 13), "3 John": (1, 14), "Jude": (1, 25), "Revelation": (22, 404)
    ]
    static let long: [String: Double] = [
        "Psalms:119": 176, "Psalms:78": 72, "Psalms:89": 52, "Numbers:7": 89, "1 Kings:8": 66,
        "Genesis:24": 67, "Matthew:26": 75, "Luke:1": 80, "Acts:7": 60, "1 Chronicles:6": 81,
        "Ezekiel:16": 63, "Jeremiah:51": 64, "Deuteronomy:28": 68, "Joshua:15": 63,
        "1 Samuel:17": 58, "Exodus:12": 51, "Job:38": 41
    ]
    static let order: [(String, Int, Int)] = [
        ("1 Samuel", 1, 31), ("2 Samuel", 1, 24), ("Ruth", 1, 4), ("Psalms", 1, 41),
        ("Genesis", 1, 50), ("Mark", 1, 16), ("Exodus", 1, 40), ("Proverbs", 1, 15),
        ("1 Kings", 1, 22), ("2 Kings", 1, 25), ("Psalms", 42, 72), ("Acts", 1, 28),
        ("Leviticus", 1, 27), ("Ecclesiastes", 1, 12), ("Numbers", 1, 36), ("Jonah", 1, 4),
        ("Deuteronomy", 1, 34), ("Psalms", 73, 89), ("Joshua", 1, 24), ("Judges", 1, 21),
        ("John", 1, 21), ("Job", 1, 42), ("Song of Songs", 1, 8), ("Isaiah", 1, 39),
        ("Psalms", 90, 106), ("Luke", 1, 24), ("Isaiah", 40, 66), ("Hosea", 1, 14),
        ("Jeremiah", 1, 52), ("Lamentations", 1, 5), ("Romans", 1, 16), ("Ezekiel", 1, 48),
        ("Daniel", 1, 12), ("Psalms", 107, 150), ("Ezra", 1, 10), ("Nehemiah", 1, 13),
        ("Esther", 1, 10), ("1 Chronicles", 1, 29), ("2 Chronicles", 1, 36), ("Proverbs", 16, 31),
        ("Matthew", 1, 28), ("Joel", 1, 3), ("Amos", 1, 9), ("Obadiah", 1, 1), ("Micah", 1, 7),
        ("Nahum", 1, 3), ("Habakkuk", 1, 3), ("Zephaniah", 1, 3), ("Haggai", 1, 2),
        ("Zechariah", 1, 14), ("Malachi", 1, 4), ("1 Corinthians", 1, 16), ("2 Corinthians", 1, 13),
        ("Galatians", 1, 6), ("Ephesians", 1, 6), ("Philippians", 1, 4), ("Colossians", 1, 4),
        ("1 Thessalonians", 1, 5), ("2 Thessalonians", 1, 3), ("1 Timothy", 1, 6),
        ("2 Timothy", 1, 4), ("Titus", 1, 3), ("Philemon", 1, 1), ("Hebrews", 1, 13),
        ("James", 1, 5), ("1 Peter", 1, 5), ("2 Peter", 1, 3), ("1 John", 1, 5),
        ("2 John", 1, 1), ("3 John", 1, 1), ("Jude", 1, 1), ("Revelation", 1, 22)
    ]

    /// Chapters grouped into days of about 60 verses, never splitting a chapter.
    public static let days: [PlanDay] = {
        var out: [PlanDay] = []
        for (name, from, to) in order {
            let b = books[name]!, avg = Double(b.verses) / Double(b.chapters)
            func v(_ c: Int) -> Double { long["\(name):\(c)"] ?? avg }
            var groups: [(Int, Int, Double)] = [], c = from
            while c <= to {
                let start = c
                var total = v(c); c += 1
                while c <= to && total + v(c) <= Program.ceiling { total += v(c); c += 1 }
                groups.append((start, c - 1, total))
            }
            if groups.count > 1, groups[groups.count - 1].2 < Program.minVerses {
                let last = groups.removeLast()
                if groups[groups.count - 1].2 + last.2 <= Program.ceiling + 18 {
                    groups[groups.count - 1].1 = last.1
                    groups[groups.count - 1].2 += last.2
                } else { groups.append(last) }
            }
            for g in groups {
                out.append(PlanDay(day: out.count + 1, book: name,
                                   read: g.0 == g.1 ? "\(name) \(g.0)" : "\(name) \(g.0)–\(g.1)",
                                   verses: Int(Fmt.jsRound(g.2)),
                                   min: max(1, Int(Fmt.jsRound(g.2 / Program.versesPerMinute)))))
            }
        }
        return out
    }()
    public static var count: Int { days.count }
    public static func day(_ n: Int) -> PlanDay { days[max(1, min(n, days.count)) - 1] }
}
