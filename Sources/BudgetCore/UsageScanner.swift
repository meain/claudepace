import Foundation

public struct ModelUsage: Sendable {
    public var cost: Double = 0
    public var costToday: Double = 0
    public var messages = 0
    public var inputTokens = 0
    public var outputTokens = 0
    public var cacheWriteTokens = 0
    public var cacheReadTokens = 0
}

public struct ProjectUsage: Sendable {
    public var cost: Double = 0
    public var costToday: Double = 0
    public var messages = 0
}

public struct SessionUsage: Sendable {
    public var project: String
    /// The session's name (`/rename` title, else the generated one); nil if it has none.
    public var title: String?
    public var cost: Double = 0
    public var messages = 0
    public var start: Date
    public var end: Date
}

public struct UsageSummary: Sendable {
    public var total: Double = 0
    public var totalToday: Double = 0
    public var byModel: [String: ModelUsage] = [:]
    /// Keyed by the project directory's name (last component of the session's cwd).
    public var byProject: [String: ProjectUsage] = [:]
    /// Spend per local calendar day, keyed by the start of that day.
    public var byDay: [Date: Double] = [:]
    /// Keyed by Claude Code session id.
    public var bySession: [String: SessionUsage] = [:]
    /// Models seen in the logs with no price; their usage is not counted.
    public var unpricedModels: Set<String> = []
    public var messages: Int { byModel.values.reduce(0) { $0 + $1.messages } }

    /// Models by descending cost.
    public var models: [(name: String, usage: ModelUsage)] {
        byModel.sorted { $0.value.cost > $1.value.cost }.map { ($0.key, $0.value) }
    }

    /// Projects by descending cost.
    public var projects: [(name: String, usage: ProjectUsage)] {
        byProject.sorted { $0.value.cost > $1.value.cost }.map { ($0.key, $0.value) }
    }

    /// Sessions by descending cost.
    public var sessions: [(id: String, usage: SessionUsage)] {
        bySession.sorted { $0.value.cost > $1.value.cost }.map { ($0.key, $0.value) }
    }

    public init() {}

    mutating func add(_ e: UsageEntry, cost: Double, today: Bool, day: Date) {
        total += cost
        byDay[day, default: 0] += cost
        var s = bySession[e.session, default: SessionUsage(project: e.project, start: e.date, end: e.date)]
        s.cost += cost
        s.messages += 1
        s.start = min(s.start, e.date)
        s.end = max(s.end, e.date)
        bySession[e.session] = s
        var p = byProject[e.project, default: ProjectUsage()]
        p.cost += cost
        p.messages += 1
        if today { p.costToday += cost }
        byProject[e.project] = p
        var m = byModel[e.model, default: ModelUsage()]
        m.cost += cost
        m.messages += 1
        m.inputTokens += e.input
        m.outputTokens += e.output
        m.cacheWriteTokens += e.cacheWrite5m + e.cacheWrite1h
        m.cacheReadTokens += e.cacheRead
        if today {
            totalToday += cost
            m.costToday += cost
        }
        byModel[e.model] = m
    }
}

/// Parsed log entries per file, reused while a file's size and mtime are unchanged.
/// Not thread-safe; use from one scan at a time.
public final class ScanCache: @unchecked Sendable {
    fileprivate struct FileEntry {
        let size: Int
        let mtime: Date
        let since: Date
        let entries: [UsageEntry]
        /// Session id → title (a `/rename` title beats the generated one).
        let titles: [String: String]
    }
    fileprivate var files: [URL: FileEntry] = [:]

    public init() {}
}

struct UsageEntry {
    /// message.id + requestId; nil when either is missing.
    let key: String?
    let date: Date
    let model: String
    let project: String
    let session: String
    let input, output, cacheWrite5m, cacheWrite1h, cacheRead: Int

    func cost(_ p: ModelPrice) -> Double {
        Double(input) * p.input + Double(output) * p.output
            + Double(cacheWrite5m) * p.cacheWrite5m + Double(cacheWrite1h) * p.cacheWrite1h
            + Double(cacheRead) * p.cacheRead
    }
}

/// Computes spend from Claude Code's session logs (`<config>/projects/**/*.jsonl`),
/// the same data ccusage reads.
public struct UsageScanner: Sendable {
    public let roots: [URL]
    public let prices: PriceTable

    public init(roots: [URL] = UsageScanner.defaultRoots(), prices: PriceTable) {
        self.roots = roots
        self.prices = prices
    }

    /// `$CLAUDE_CONFIG_DIR` (comma-separated) if set, else ~/.config/claude and ~/.claude.
    public static func defaultRoots() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dirs: [URL]
        if let env = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !env.isEmpty {
            dirs = env.split(separator: ",").map {
                URL(fileURLWithPath: $0.trimmingCharacters(in: .whitespaces))
            }
        } else {
            dirs = [home.appending(path: ".config/claude"), home.appending(path: ".claude")]
        }
        return dirs.map { $0.appending(path: "projects") }
    }

    /// Entries at or after `todayStart` also count toward the `…Today` totals.
    public func scan(from start: Date, to end: Date = Date(), todayStart: Date? = nil,
                     cache: ScanCache = ScanCache()) -> UsageSummary {
        // Claude Code logs a response several times while it streams (and again when a
        // session is resumed); token counts only grow, so keep the costliest copy.
        var byKey: [String: (entry: UsageEntry, cost: Double)] = [:]
        var summary = UsageSummary()
        var titles: [String: String] = [:]
        let todayStart = todayStart ?? end

        let calendar = Calendar.current
        func add(_ e: UsageEntry, _ cost: Double) {
            summary.add(e, cost: cost, today: e.date >= todayStart, day: calendar.startOfDay(for: e.date))
        }

        for (url, size, mtime) in jsonlFiles(modifiedAfter: start) {
            let entries: [UsageEntry]
            if let c = cache.files[url], c.size == size, c.mtime == mtime, c.since <= start {
                entries = c.entries
                titles.merge(c.titles) { _, new in new }
            } else {
                let parsed = parse(url, since: start)
                entries = parsed.entries
                titles.merge(parsed.titles) { _, new in new }
                cache.files[url] = .init(size: size, mtime: mtime, since: start,
                                         entries: parsed.entries, titles: parsed.titles)
            }
            for e in entries where e.date >= start && e.date < end {
                guard let p = prices.price(for: e.model) else {
                    summary.unpricedModels.insert(e.model)
                    continue
                }
                let cost = e.cost(p)
                if let key = e.key {
                    if cost > byKey[key]?.cost ?? -1 { byKey[key] = (e, cost) }
                } else {
                    add(e, cost)
                }
            }
        }
        for (e, cost) in byKey.values { add(e, cost) }
        for (id, title) in titles { summary.bySession[id]?.title = title }
        return summary
    }

    private struct Line: Decodable {
        struct Message: Decodable {
            let id: String?
            let model: String?
            let usage: Usage?
        }
        struct Usage: Decodable {
            struct CacheCreation: Decodable {
                let ephemeral_1h_input_tokens: Int?
            }
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_creation_input_tokens: Int?
            let cache_read_input_tokens: Int?
            let cache_creation: CacheCreation?
        }
        let timestamp: String?
        let requestId: String?
        let sessionId: String?
        let cwd: String?
        let message: Message?
    }

    private struct TitleLine: Decodable {
        let type: String?
        let aiTitle: String?
        let customTitle: String?
        let sessionId: String?
    }

    private func parse(_ url: URL, since start: Date) -> (entries: [UsageEntry], titles: [String: String]) {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return ([], [:]) }
        let titleMarker = Data(#"-title""#.utf8)
        var aiTitles: [String: String] = [:]
        var customTitles: [String: String] = [:]
        let decoder = JSONDecoder()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let usageMarker = Data(#""usage""#.utf8)
        let fallbackProject = url.deletingLastPathComponent().lastPathComponent
        let fallbackSession = url.deletingPathExtension().lastPathComponent

        var out: [UsageEntry] = []
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
            if line.range(of: usageMarker) == nil, line.range(of: titleMarker) != nil,
               let t = try? decoder.decode(TitleLine.self, from: line) {
                let id = t.sessionId ?? fallbackSession
                if t.type == "custom-title", let title = t.customTitle { customTitles[id] = title }
                if t.type == "ai-title", let title = t.aiTitle { aiTitles[id] = title }
                continue
            }
            guard line.range(of: usageMarker) != nil,
                  let entry = try? decoder.decode(Line.self, from: line),
                  let msg = entry.message, let usage = msg.usage, let model = msg.model,
                  model != "<synthetic>",
                  let ts = entry.timestamp,
                  let date = isoFrac.date(from: ts) ?? iso.date(from: ts),
                  date >= start else { continue }

            let cacheWrite = usage.cache_creation_input_tokens ?? 0
            let w1h = min(usage.cache_creation?.ephemeral_1h_input_tokens ?? 0, cacheWrite)
            let key = msg.id.flatMap { id in entry.requestId.map { id + ":" + $0 } }
            let project = entry.cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
                .flatMap { $0.isEmpty ? nil : $0 } ?? fallbackProject
            out.append(UsageEntry(key: key, date: date, model: model, project: project,
                                  session: entry.sessionId ?? fallbackSession,
                                  input: usage.input_tokens ?? 0, output: usage.output_tokens ?? 0,
                                  cacheWrite5m: cacheWrite - w1h, cacheWrite1h: w1h,
                                  cacheRead: usage.cache_read_input_tokens ?? 0))
        }
        return (out, aiTitles.merging(customTitles) { _, custom in custom })
    }

    private func jsonlFiles(modifiedAfter start: Date) -> [(URL, Int, Date)] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        var out: [(URL, Int, Date)] = []
        for root in roots {
            guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys,
                                                               options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in walker where url.pathExtension == "jsonl" {
                guard let v = try? url.resourceValues(forKeys: Set(keys)),
                      let mtime = v.contentModificationDate, let size = v.fileSize,
                      // A file untouched since the window opened can't contain entries in it.
                      mtime >= start else { continue }
                out.append((url, size, mtime))
            }
        }
        return out
    }
}
