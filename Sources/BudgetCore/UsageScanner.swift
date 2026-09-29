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

public struct UsageSummary: Sendable {
    public var total: Double = 0
    public var totalToday: Double = 0
    public var byModel: [String: ModelUsage] = [:]
    /// Keyed by the project directory's name (last component of the session's cwd).
    public var byProject: [String: ProjectUsage] = [:]
    /// Spend per local calendar day, keyed by the start of that day.
    public var byDay: [Date: Double] = [:]
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

    public init() {}

    mutating func add(_ e: UsageEntry, cost: Double, today: Bool, day: Date) {
        total += cost
        byDay[day, default: 0] += cost
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
        let todayStart = todayStart ?? end

        let calendar = Calendar.current
        func add(_ e: UsageEntry, _ cost: Double) {
            summary.add(e, cost: cost, today: e.date >= todayStart, day: calendar.startOfDay(for: e.date))
        }

        for (url, size, mtime) in jsonlFiles(modifiedAfter: start) {
            let entries: [UsageEntry]
            if let c = cache.files[url], c.size == size, c.mtime == mtime, c.since <= start {
                entries = c.entries
            } else {
                entries = parse(url, since: start)
                cache.files[url] = .init(size: size, mtime: mtime, since: start, entries: entries)
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
        let cwd: String?
        let message: Message?
    }

    private func parse(_ url: URL, since start: Date) -> [UsageEntry] {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return [] }
        let decoder = JSONDecoder()
        let isoFrac = ISO8601DateFormatter()
        isoFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let iso = ISO8601DateFormatter()
        let usageMarker = Data(#""usage""#.utf8)
        let fallbackProject = url.deletingLastPathComponent().lastPathComponent

        var out: [UsageEntry] = []
        for line in data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
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
                                  input: usage.input_tokens ?? 0, output: usage.output_tokens ?? 0,
                                  cacheWrite5m: cacheWrite - w1h, cacheWrite1h: w1h,
                                  cacheRead: usage.cache_read_input_tokens ?? 0))
        }
        return out
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
