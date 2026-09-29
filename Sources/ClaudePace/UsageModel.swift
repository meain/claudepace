import BudgetCore
import Combine
import Foundation

@MainActor
final class UsageModel: ObservableObject {
    @Published var monthlyBudget: Double {
        didSet { UserDefaults.standard.set(monthlyBudget, forKey: "monthlyBudget") }
    }
    @Published var reservePercent: Double {
        didSet { UserDefaults.standard.set(reservePercent, forKey: "reservePercent") }
    }

    enum MenuBarMode: String, CaseIterable {
        case days = "Days", percent = "% left", dollars = "$ left"
    }

    @Published var menuBarMode: MenuBarMode {
        didSet { UserDefaults.standard.set(menuBarMode.rawValue, forKey: "menuBarMode") }
    }

    @Published private(set) var summary: UsageSummary?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isLoading = false
    @Published private(set) var pricingSource = "built-in"

    private var prices = PriceTable.builtin
    private var pricesFetchedAt: Date?
    private let scanCache = ScanCache()

    private static let refreshInterval: TimeInterval = 5 * 60
    private static let pricesMaxAge: TimeInterval = 24 * 60 * 60
    private static let liteLLMURL = URL(string:
        "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    private static var pricesCacheFile: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appending(path: "dev.meain.claudepace")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appending(path: "litellm-prices.json")
    }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["monthlyBudget": 2000.0, "reservePercent": 10.0])
        monthlyBudget = d.double(forKey: "monthlyBudget")
        reservePercent = d.double(forKey: "reservePercent")
        menuBarMode = d.string(forKey: "menuBarMode").flatMap(MenuBarMode.init) ?? .days

        if let data = try? Data(contentsOf: Self.pricesCacheFile), let t = PriceTable.fromLiteLLM(data) {
            prices = PriceTable.builtin.merging(t)
            pricingSource = "LiteLLM (cached)"
        }

        Task { [weak self] in
            while let self {
                await self.refresh()
                try? await Task.sleep(for: .seconds(Self.refreshInterval))
            }
        }
    }

    var status: BudgetStatus? {
        guard let summary else { return nil }
        return BudgetStatus(monthlyBudget: monthlyBudget, reservePercent: reservePercent,
                            spent: summary.total, now: Date())
    }

    var menuBarLabel: String {
        guard let status else { return "…" }
        let today = summary?.totalToday ?? 0
        let left = status.paceLeftToday(spentToday: today)
        let sign = left < 0 ? "−" : ""
        switch menuBarMode {
        case .days:
            return status.label
        case .percent:
            let target = status.todayTarget(spentToday: today)
            let pct = target > 0 ? Int((abs(left) / target * 100).rounded()) : 0
            return "\(sign)\(pct)%"
        case .dollars:
            return "\(sign)$\(Int(abs(left).rounded()))"
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        await refreshPricesIfStale()
        let prices = self.prices
        let cache = scanCache
        let now = Date()
        let start = BudgetStatus.monthStart(of: now)
        let today = Calendar.current.startOfDay(for: now)
        summary = await Task.detached(priority: .utility) {
            UsageScanner(prices: prices).scan(from: start, to: now, todayStart: today, cache: cache)
        }.value
        lastUpdated = now
    }

    /// Keeps the built-in table when offline; a failed fetch retries next refresh.
    private func refreshPricesIfStale() async {
        if let t = pricesFetchedAt, Date().timeIntervalSince(t) < Self.pricesMaxAge { return }
        guard let (data, resp) = try? await URLSession.shared.data(from: Self.liteLLMURL),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let table = PriceTable.fromLiteLLM(data) else { return }
        try? data.write(to: Self.pricesCacheFile)
        prices = PriceTable.builtin.merging(table)
        pricesFetchedAt = Date()
        pricingSource = "LiteLLM"
    }
}
