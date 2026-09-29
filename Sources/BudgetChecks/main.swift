// Budget math checks. Run with `swift run BudgetChecks` (XCTest/Testing need full Xcode).
// `BudgetChecks --scan [litellm.json]` prints this month's spend from the Claude Code logs.
import BudgetCore
import Foundation

if CommandLine.arguments.count > 1, CommandLine.arguments[1] == "--scan" {
    var prices = PriceTable.builtin
    if CommandLine.arguments.count > 2,
       let data = FileManager.default.contents(atPath: CommandLine.arguments[2]),
       let t = PriceTable.fromLiteLLM(data) {
        prices = prices.merging(t)
    }
    let clock = ContinuousClock()
    let scanner = UsageScanner(prices: prices)
    let cache = ScanCache()
    let start = BudgetStatus.monthStart(of: Date())
    var summary = UsageSummary()
    let today = Calendar.current.startOfDay(for: Date())
    let cold = clock.measure { summary = scanner.scan(from: start, todayStart: today, cache: cache) }
    let warm = clock.measure { summary = scanner.scan(from: start, todayStart: today, cache: cache) }
    for (model, u) in summary.models {
        print(String(format: "%-32@ $%10.2f  today $%8.2f  msgs %6d", model as NSString, u.cost, u.costToday, u.messages))
    }
    for (project, u) in summary.projects.prefix(5) {
        print(String(format: "project %-24@ $%10.2f  today $%8.2f", project as NSString, u.cost, u.costToday))
    }
    print("days with spend: \(summary.byDay.count)")
    print(String(format: "%-32@ $%10.2f  today $%8.2f", "total" as NSString, summary.total, summary.totalToday))
    print("messages: \(summary.messages), unpriced: \(summary.unpricedModels.sorted()), cold: \(cold), warm: \(warm)")
    exit(0)
}

private let utcCalendar: Calendar = {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal
}()

private func status(spent: Double, reserve: Double = 0, _ s: String) -> BudgetStatus {
    BudgetStatus(monthlyBudget: 2000, reservePercent: reserve, spent: spent,
                 now: ISO8601DateFormatter().date(from: s)!, calendar: utcCalendar)
}

nonisolated(unsafe) private var failures = 0
private func check(_ cond: Bool, _ msg: String, line: Int = #line) {
    if !cond {
        failures += 1
        print("FAIL line \(line): \(msg)")
    }
}

// Sept: 30 days, no reserve → $66.67/day; day 3 → 2 days expected.
do {
    let s = status(spent: 2000.0 * 2 / 30, "2026-09-03T12:00:00Z")
    check(s.completedDays == 2, "completedDays")
    check(abs(s.daysAhead) < 1e-9, "on pace")
    check(s.label == "±0d", "label \(s.label)")
}

do {
    let s = status(spent: 0, "2026-09-03T12:00:00Z")
    check(s.label == "+2d", "under spend label \(s.label)")
}

do {
    let s = status(spent: 2000.0 / 30 * 4.5, "2026-09-03T12:00:00Z")
    check(s.label == "−2d", "over spend label \(s.label)")
}

do {
    let s = status(spent: 0, reserve: 10, "2026-02-10T00:00:00Z")
    check(s.daysInMonth == 28, "feb days")
    check(abs(s.usableBudget - 1800) < 1e-9, "usable budget")
    check(abs(s.dailyAllowance - 1800.0 / 28) < 1e-9, "daily allowance")
}

// Day 3 of 30: 28 days remain; $150 spent before today, $50 today.
do {
    let s = status(spent: 200, "2026-09-03T12:00:00Z")
    check(s.daysRemaining == 28, "daysRemaining")
    check(abs(s.todayTarget(spentToday: 50) - 1850.0 / 28) < 1e-9, "todayTarget")
    check(abs(s.paceLeftToday(spentToday: 50) - (1850.0 / 28 - 50)) < 1e-9, "paceLeftToday")
    let over = status(spent: 2500, "2026-09-03T12:00:00Z")
    check(over.todayTarget(spentToday: 0) == 0, "no target once budget is spent")
}

do {
    let t = PriceTable.builtin
    check(t.price(for: "claude-haiku-4-5-20251001") == t.price(for: "claude-haiku-4-5"), "dated suffix lookup")
    check(t.price(for: "anthropic/claude-opus-5-5") != nil, "anthropic/ prefix lookup")
    check(t.price(for: "gpt-5") == nil, "unknown model")
}

print(failures == 0 ? "All checks passed" : "\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
