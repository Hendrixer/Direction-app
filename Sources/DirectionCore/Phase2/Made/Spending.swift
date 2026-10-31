import Foundation
import Darwin

/// What spend is for, in Settings › Engines › Spent this month.
public enum SpendKind: String, Codable, CaseIterable, Sendable {
    case music, soundEffect, voice, still, shot, `extension`, bridge, changedShot, slowMotion, upscale, looking
    /// Direction checking what was made (decisions.md).
    case checking
    /// Legend rows: every kind of shot is "New shots".
    public var group: String {
        switch self {
        case .music: "Music"; case .soundEffect: "Sound effects"; case .voice: "Voice"; case .still: "Stills"; case .looking: "Looking at footage"; case .checking: "Checking"
        case .shot, .extension, .bridge, .changedShot, .slowMotion, .upscale: "New shots"
        }
    }
    public static let groups = ["Music", "Sound effects", "Voice", "New shots", "Stills", "Looking at footage", "Checking"]
}

/// One request's money: reserved at its estimate before it's sent, settled at what OpenRouter reported.
public struct SpendEntry: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var at: Double
    public var kind: SpendKind
    public var service: String
    public var version: String
    public var estimate: Double
    /// What OpenRouter reported (`usage.cost`); nil while the request is out.
    public var spend: Double?
    public var filmID: String?
    public var turnoverID: String?
    public var assetIDs: [String]?
    /// The spend question whose yes let this request past the turnover's limit. A yes covers the plan it priced.
    public var questionID: String?
    public init(id: String = newID("spend"), at: Date = Date(), kind: SpendKind, service: String = "openrouter", version: String, estimate: Double, spend: Double? = nil, filmID: String? = nil, turnoverID: String? = nil, questionID: String? = nil) {
        self.id = id; self.at = at.timeIntervalSince1970; self.kind = kind; self.service = service; self.version = version; self.estimate = estimate; self.spend = spend; self.filmID = filmID; self.turnoverID = turnoverID; self.questionID = questionID
    }
    /// Counted against the limits: what was spent, or the estimate while it's out.
    public var amount: Double { spend ?? estimate }
    public var pending: Bool { spend == nil }
}

/// The director's limits, in the shared suite so the editor's tools read what Settings chose.
extension SharedSettings {
    public enum SpendKey {
        public static let askAbove = "spendAskAbovePerTurnover", stopAt = "spendStopAtPerMonth"
    }
    public static let askAboveChoices: [Double] = [1, 5, 10, 25, 50]
    /// 0 is "No limit".
    public static let stopAtChoices: [Double] = [25, 50, 100, 250, 0]

    /// Ask before spending more than this in one turnover. Default $5.00.
    public static var spendAskAbove: Double { OpenRouter.overrides.limits?.askAbove ?? (defaults.object(forKey: SpendKey.askAbove) as? Double) ?? 5 }
    /// Stop for the month at this; nil is no limit. Default $50.00.
    public static var spendStopAt: Double? {
        if let limits = OpenRouter.overrides.limits { return limits.stopAt }
        let v = (defaults.object(forKey: SpendKey.stopAt) as? Double) ?? 50
        return v > 0 ? v : nil
    }
}

public struct SpendLimits: Sendable, Equatable {
    public var askAbove: Double
    public var stopAt: Double?
    public init(askAbove: Double, stopAt: Double?) { self.askAbove = askAbove; self.stopAt = stopAt }
}

/// Whether a request may go out.
public enum SpendCheck: Equatable, Sendable {
    case ok
    /// More than the turnover's limit and no yes to a spend question for it.
    case overLimit(estimate: Double, spent: Double, limit: Double)
    /// Past the month's cap. Nothing overrides it.
    case cap(estimate: Double, spent: Double, cap: Double)

    public static func of(estimate: Double, turnoverSpent: Double, monthSpent: Double, askAbove: Double, stopAt: Double?, approved: Bool) -> SpendCheck {
        let cent = 0.005
        if let stopAt, monthSpent + estimate > stopAt + cent { return .cap(estimate: estimate, spent: monthSpent, cap: stopAt) }
        if !approved, turnoverSpent + estimate > askAbove + cent { return .overLimit(estimate: estimate, spent: turnoverSpent, limit: askAbove) }
        return .ok
    }
}

/// This Mac's record of every request's spend, by month. The app and the editor's tools both write it,
/// so every change happens under an exclusive `flock` on a sidecar lock file.
public enum SpendLedger {
    public static var supportDirectory: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Direction") }
    /// Tests use `OpenRouter.Overrides.ledger`.
    public static var url: URL { OpenRouter.overrides.ledger ?? supportDirectory.appendingPathComponent("spend.json") }

    struct File: Codable { var entries: [SpendEntry] = [] }

    /// Runs `body` with the ledger locked against every other process, and saves what it leaves.
    @discardableResult
    public static func transaction<T>(_ body: (inout [SpendEntry]) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let fd = open(url.path + ".lock", O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw DirectionError("ledger_unavailable", "Direction couldn\u{2019}t open its spend record.") }
        defer { close(fd) }
        while flock(fd, LOCK_EX) != 0 { guard errno == EINTR else { throw DirectionError("ledger_unavailable", "Direction couldn\u{2019}t lock its spend record.") } }
        defer { flock(fd, LOCK_UN) }
        var file = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(File.self, from: $0) } ?? File()
        let before = file.entries
        let result = try body(&file.entries)
        if file.entries != before {
            // Keep thirteen months: this one and a year of history.
            let cutoff = Calendar.current.date(byAdding: .month, value: -13, to: Date())!.timeIntervalSince1970
            file.entries.removeAll { $0.at < cutoff }
            try JSONEncoder.direction.encode(file).write(to: url, options: .atomic)
        }
        return result
    }

    public static func entries() -> [SpendEntry] { (try? transaction { $0 }) ?? [] }

    /// Entries since the 1st of this month. The month resets on the 1st.
    public static func month(_ entries: [SpendEntry], now: Date = Date()) -> [SpendEntry] {
        let start = Calendar.current.dateInterval(of: .month, for: now)?.start.timeIntervalSince1970 ?? 0
        return entries.filter { $0.at >= start }
    }
    public static func monthSpent(_ entries: [SpendEntry], now: Date = Date()) -> Double { month(entries, now: now).reduce(0) { $0 + $1.amount } }
    public static func turnoverSpent(_ entries: [SpendEntry], filmID: String?, turnoverID: String?) -> Double {
        guard let turnoverID else { return 0 }
        return entries.filter { $0.turnoverID == turnoverID && $0.filmID == filmID }.reduce(0) { $0 + $1.amount }
    }
    /// This month by legend group, for the meter.
    public static func byGroup(_ entries: [SpendEntry], now: Date = Date()) -> [(group: String, spent: Double)] {
        let m = month(entries, now: now)
        return SpendKind.groups.compactMap { g in
            let total = m.filter { $0.kind.group == g }.reduce(0) { $0 + $1.amount }
            return total > 0.0049 ? (g, total) : nil
        }
    }

    /// A yes covers the plan it priced, and a little over: its estimate plus 10%.
    public static func budget(forEstimate estimate: Double) -> Double { (estimate * 1.1 * 100).rounded() / 100 }

    /// Checks both limits and holds the estimate in one locked step, so two processes can't both slip under a limit.
    /// `approvedBy` is a spend question the director said yes to, with the `budget` it allows: every request that
    /// names it may go past the turnover's limit until together they've used that much.
    public static func reserve(_ entry: SpendEntry, approvedBy question: String? = nil, budget: Double? = nil, askAbove: Double = SharedSettings.spendAskAbove, stopAt: Double? = SharedSettings.spendStopAt, now: Date = Date()) throws -> SpendCheck {
        try transaction { entries in
            if let question {
                let used = entries.filter { $0.questionID == question }.reduce(0) { $0 + $1.amount }
                if let budget, used + entry.estimate > budget + 0.005 {
                    throw DirectionError("spend_over_question", "The director agreed to about \(MadeFormat.money(budget)) for that plan and \(MadeFormat.money(used)) of it is used; this would cost about \(MadeFormat.money(entry.estimate)). Ask again for the rest.")
                }
            }
            let check = SpendCheck.of(estimate: entry.estimate, turnoverSpent: turnoverSpent(entries, filmID: entry.filmID, turnoverID: entry.turnoverID), monthSpent: monthSpent(entries, now: now), askAbove: askAbove, stopAt: stopAt, approved: question != nil)
            if check == .ok { var e = entry; e.questionID = question; e.spend = nil; entries.append(e) }
            return check
        }
    }
    /// What OpenRouter reported. Without a report, the estimate stands as the spend.
    public static func settle(_ id: String, spend: Double?, assetIDs: [String]) throws {
        try transaction { entries in
            guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[i].spend = spend ?? entries[i].estimate; entries[i].assetIDs = assetIDs
        }
    }
    /// A request that failed before anything was made. If OpenRouter still charged (a failed shot can), that's recorded.
    public static func release(_ id: String, charged: Double? = nil) throws {
        try transaction { entries in
            guard let i = entries.firstIndex(where: { $0.id == id }) else { return }
            if let charged, charged > 0 { entries[i].spend = charged } else { entries.remove(at: i) }
        }
    }
    public static func record(_ entry: SpendEntry) throws { try transaction { $0.append(entry) } }
}
