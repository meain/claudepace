import Foundation

/// Machine-readable dumps of a `UsageSummary`.
public enum Export {
    public enum Grouping: String, CaseIterable, Sendable {
        case day, model, project, session
    }

    /// Flat table (header row first) for one grouping, most expensive / earliest first.
    public static func table(_ s: UsageSummary, by grouping: Grouping) -> [[String]] {
        func money(_ v: Double) -> String { String(format: "%.4f", v) }
        switch grouping {
        case .day:
            return [["date", "cost_usd"]]
                + s.byDay.sorted { $0.key < $1.key }.map { [dayString($0.key), money($0.value)] }
        case .model:
            return [["model", "cost_usd", "cost_today_usd", "messages", "input_tokens",
                     "output_tokens", "cache_write_tokens", "cache_read_tokens"]]
                + s.models.map { m in
                    [m.name, money(m.usage.cost), money(m.usage.costToday), "\(m.usage.messages)",
                     "\(m.usage.inputTokens)", "\(m.usage.outputTokens)",
                     "\(m.usage.cacheWriteTokens)", "\(m.usage.cacheReadTokens)"]
                }
        case .project:
            return [["project", "cost_usd", "cost_today_usd", "messages"]]
                + s.projects.map { [$0.name, money($0.usage.cost), money($0.usage.costToday), "\($0.usage.messages)"] }
        case .session:
            return [["session", "title", "project", "cost_usd", "messages", "start", "end"]]
                + s.sessions.map { x in
                    [x.id, x.usage.title ?? "", x.usage.project, money(x.usage.cost), "\(x.usage.messages)",
                     timestamp(x.usage.start), timestamp(x.usage.end)]
                }
        }
    }

    public static func csv(_ s: UsageSummary, by grouping: Grouping) -> String {
        table(s, by: grouping).map { $0.map(escape).joined(separator: ",") }.joined(separator: "\n") + "\n"
    }

    /// Everything in one document. `previous` adds last month's daily spend for comparison.
    public static func json(_ s: UsageSummary, month: Date, previous: UsageSummary? = nil) -> String {
        struct Doc: Encodable {
            struct Day: Encodable { let date: String; let cost: Double }
            struct Model: Encodable {
                let model: String; let cost, costToday: Double; let messages: Int
                let inputTokens, outputTokens, cacheWriteTokens, cacheReadTokens: Int
            }
            struct Project: Encodable { let project: String; let cost, costToday: Double; let messages: Int }
            struct Session: Encodable {
                let session, project: String; let title: String?
                let cost: Double; let messages: Int
                let start, end: String
            }
            let month: String
            let total, totalToday: Double
            let previousMonthTotal: Double?
            let byDay: [Day]
            let previousMonthByDay: [Day]?
            let byModel: [Model]
            let byProject: [Project]
            let sessions: [Session]
            let unpricedModels: [String]
        }
        func days(_ s: UsageSummary) -> [Doc.Day] {
            s.byDay.sorted { $0.key < $1.key }.map { .init(date: dayString($0.key), cost: $0.value) }
        }
        let doc = Doc(
            month: String(dayString(month).prefix(7)),
            total: s.total, totalToday: s.totalToday,
            previousMonthTotal: previous?.total,
            byDay: days(s),
            previousMonthByDay: previous.map(days),
            byModel: s.models.map { m in
                .init(model: m.name, cost: m.usage.cost, costToday: m.usage.costToday,
                      messages: m.usage.messages, inputTokens: m.usage.inputTokens,
                      outputTokens: m.usage.outputTokens, cacheWriteTokens: m.usage.cacheWriteTokens,
                      cacheReadTokens: m.usage.cacheReadTokens)
            },
            byProject: s.projects.map {
                .init(project: $0.name, cost: $0.usage.cost, costToday: $0.usage.costToday, messages: $0.usage.messages)
            },
            sessions: s.sessions.map {
                .init(session: $0.id, project: $0.usage.project, title: $0.usage.title, cost: $0.usage.cost, messages: $0.usage.messages,
                      start: timestamp($0.usage.start), end: timestamp($0.usage.end))
            },
            unpricedModels: s.unpricedModels.sorted())
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.keyEncodingStrategy = .convertToSnakeCase
        return String(decoding: (try? enc.encode(doc)) ?? Data(), as: UTF8.self) + "\n"
    }

    private static func escape(_ f: String) -> String {
        f.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
            ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
    }

    private static func dayString(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    private static func timestamp(_ d: Date) -> String {
        ISO8601DateFormatter().string(from: d)
    }
}
