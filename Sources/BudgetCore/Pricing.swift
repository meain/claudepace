import Foundation

/// USD per token.
public struct ModelPrice: Sendable, Equatable {
    public let input: Double
    public let output: Double
    public let cacheWrite5m: Double
    public let cacheWrite1h: Double
    public let cacheRead: Double

    public init(input: Double, output: Double, cacheWrite5m: Double? = nil,
                cacheWrite1h: Double? = nil, cacheRead: Double? = nil) {
        self.input = input
        self.output = output
        self.cacheWrite5m = cacheWrite5m ?? input * 1.25
        self.cacheWrite1h = cacheWrite1h ?? input * 2
        self.cacheRead = cacheRead ?? input * 0.1
    }

    /// Per-million-token convenience for the built-in table.
    static func mtok(_ i: Double, _ o: Double, read: Double? = nil) -> ModelPrice {
        ModelPrice(input: i / 1e6, output: o / 1e6, cacheRead: read.map { $0 / 1e6 })
    }
}

public struct PriceTable: Sendable {
    public private(set) var prices: [String: ModelPrice]

    public init(_ prices: [String: ModelPrice]) { self.prices = prices }

    /// Fallback when the LiteLLM list can't be fetched.
    public static let builtin = PriceTable([
        "claude-fable-5-1": .mtok(10, 50, read: 0.25),
        "claude-mythos-5-1": .mtok(10, 50, read: 0.25),
        "claude-fable-5": .mtok(10, 50),
        "claude-opus-5-5": .mtok(4, 20, read: 0.20),
        "claude-opus-5": .mtok(5, 25),
        "claude-opus-4-8": .mtok(5, 25),
        "claude-opus-4-7": .mtok(5, 25),
        "claude-opus-4-6": .mtok(5, 25),
        "claude-sonnet-5-5": .mtok(2, 10),
        "claude-sonnet-5": .mtok(2, 10),
        "claude-sonnet-4-6": .mtok(3, 15),
        "claude-haiku-4-5": .mtok(1, 5),
    ])

    /// Parses LiteLLM's model_prices_and_context_window.json (the list ccusage uses).
    public static func fromLiteLLM(_ data: Data) -> PriceTable? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var out: [String: ModelPrice] = [:]
        for (name, value) in root where name.contains("claude") {
            guard let v = value as? [String: Any],
                  let input = v["input_cost_per_token"] as? Double,
                  let output = v["output_cost_per_token"] as? Double else { continue }
            out[name] = ModelPrice(input: input, output: output,
                                   cacheWrite5m: v["cache_creation_input_token_cost"] as? Double,
                                   cacheWrite1h: v["cache_creation_input_token_cost_above_1hr"] as? Double,
                                   cacheRead: v["cache_read_input_token_cost"] as? Double)
        }
        return out.isEmpty ? nil : PriceTable(out)
    }

    /// Entries in `other` win.
    public func merging(_ other: PriceTable) -> PriceTable {
        PriceTable(prices.merging(other.prices) { _, new in new })
    }

    public func price(for model: String) -> ModelPrice? {
        let bare = model.hasPrefix("anthropic/") ? String(model.dropFirst(10)) : model
        // Drop a trailing -YYYYMMDD snapshot suffix.
        let undated = bare.replacingOccurrences(of: #"-\d{8}$"#, with: "", options: .regularExpression)
        for key in [model, bare, "anthropic/\(bare)", undated, "anthropic/\(undated)"] {
            if let p = prices[key] { return p }
        }
        return nil
    }
}
