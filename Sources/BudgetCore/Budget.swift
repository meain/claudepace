import Foundation

/// Budget pacing for a calendar month in `calendar`'s time zone (local by default).
public struct BudgetStatus: Equatable, Sendable {
    public let monthlyBudget: Double
    public let reservePercent: Double
    public let spent: Double
    public let daysInMonth: Int
    public let dayOfMonth: Int

    public init(monthlyBudget: Double, reservePercent: Double, spent: Double, now: Date,
                calendar cal: Calendar = .current) {
        self.monthlyBudget = monthlyBudget
        self.reservePercent = min(max(reservePercent, 0), 100)
        self.spent = spent
        self.daysInMonth = cal.range(of: .day, in: .month, for: now)!.count
        self.dayOfMonth = cal.component(.day, from: now)
    }

    /// Budget left after carving out the reservation.
    public var usableBudget: Double { monthlyBudget * (1 - reservePercent / 100) }
    public var reservedAmount: Double { monthlyBudget - usableBudget }
    public var dailyAllowance: Double { usableBudget / Double(daysInMonth) }

    /// Days fully elapsed before today (day 3 → 2 days).
    public var completedDays: Int { dayOfMonth - 1 }
    public var expectedSpend: Double { dailyAllowance * Double(completedDays) }

    /// Positive = under budget by that many days, negative = over.
    public var daysAhead: Double {
        guard dailyAllowance > 0 else { return 0 }
        return (expectedSpend - spent) / dailyAllowance
    }

    /// Whole days ahead/behind, truncated toward zero so ±1 means a full day.
    public var wholeDaysAhead: Int { Int(daysAhead.rounded(.towardZero)) }

    /// What can still be spent today while staying on pace.
    public var leftToday: Double { dailyAllowance * Double(dayOfMonth) - spent }
    public var remainingThisMonth: Double { usableBudget - spent }

    /// Days left in the month including today.
    public var daysRemaining: Int { daysInMonth - dayOfMonth + 1 }

    /// Today's share of what was left at the start of the day, spread over the days remaining.
    /// Unlike `dailyAllowance`, it absorbs past under/overspend.
    public func todayTarget(spentToday: Double) -> Double {
        max(usableBudget - (spent - spentToday), 0) / Double(daysRemaining)
    }

    /// Pace-aware: negative once today's target is exceeded.
    public func paceLeftToday(spentToday: Double) -> Double {
        todayTarget(spentToday: spentToday) - spentToday
    }

    public static func monthStart(of date: Date, calendar cal: Calendar = .current) -> Date {
        cal.date(from: cal.dateComponents([.year, .month], from: date))!
    }

    public var label: String {
        let d = wholeDaysAhead
        if d == 0 { return "±0d" }
        return d > 0 ? "+\(d)d" : "−\(-d)d"
    }
}
