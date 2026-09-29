import BudgetCore
import Charts
import SwiftUI

@main
struct ClaudePaceApp: App {
    @StateObject private var model = UsageModel()

    init() {
        Screenshot.runIfRequested()
    }

    var body: some Scene {
        MenuBarExtra {
            UsageView(model: model)
        } label: {
            Text(model.menuBarLabel)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Local view state; `@State` is a macro that Command Line Tools can't expand.
final class ViewState: ObservableObject {
    enum Breakdown: String, CaseIterable {
        case models = "Models", projects = "Projects", sessions = "Sessions"
    }

    @Published var showSettings = false
    @Published var breakdown: Breakdown

    init(breakdown: Breakdown = .models) { self.breakdown = breakdown }
}

private extension View {
    func card() -> some View {
        padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct UsageView: View {
    @ObservedObject var model: UsageModel
    @StateObject private var ui: ViewState

    init(model: UsageModel, breakdown: ViewState.Breakdown = .models) {
        self.model = model
        _ui = StateObject(wrappedValue: ViewState(breakdown: breakdown))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let s = model.status {
                hero(s)
                sparkline(s)
                tiles(s)
            }
            if let unpriced = model.summary?.unpricedModels, !unpriced.isEmpty {
                Text("No price for \(unpriced.sorted().joined(separator: ", ")); not counted.")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let summary = model.summary, !summary.byModel.isEmpty {
                breakdown(summary)
            }
            if ui.showSettings { settings }
            footer
        }
        .padding(14)
        .frame(width: 340)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 8) {
            Text("Claude Pace").font(.headline)
            if let s = model.status {
                Text(String(format: "%+.1f days", s.daysAhead))
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(color(s).opacity(0.18), in: Capsule())
                    .foregroundStyle(color(s))
            }
            Spacer()
            if model.isLoading { ProgressView().controlSize(.small) }
            Button {
                ui.showSettings.toggle()
            } label: {
                Image(systemName: "gearshape\(ui.showSettings ? ".fill" : "")")
            }
            .buttonStyle(.borderless)
            .help("Settings")
        }
    }

    // MARK: Hero

    private func hero(_ s: BudgetStatus) -> some View {
        let today = model.summary?.totalToday ?? 0
        let target = s.todayTarget(spentToday: today)
        let left = s.paceLeftToday(spentToday: today)
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(left >= 0 ? "LEFT TODAY" : "OVER TODAY'S TARGET")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                Text(usd(abs(left), fraction: 0))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .foregroundStyle(left >= 0 ? Color.primary : Color.red)
                    .monospacedDigit()
                Text("\(usd(today, fraction: 0)) of \(usd(target, fraction: 0)) target · "
                     + "\(s.daysRemaining) days left")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            monthBar(s)
        }
        .card()
    }

    /// Spend vs full monthly budget; the orange tail is the reserve, the tick is where spend should be today.
    private func monthBar(_ s: BudgetStatus) -> some View {
        let total = max(s.monthlyBudget, 0.01)
        let spent = min(max(s.spent / total, 0), 1)
        let expected = min(max(s.expectedSpend / total, 0), 1)
        let reserve = min(max(s.reservedAmount / total, 0), 1)
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Rectangle().fill(Color.orange.opacity(0.35))
                        .frame(width: w * reserve)
                        .offset(x: w * (1 - reserve))
                    Capsule().fill(color(s)).frame(width: w * spent)
                    Rectangle().fill(Color.primary.opacity(0.7))
                        .frame(width: 2, height: 12)
                        .offset(x: w * expected - 1)
                }
                .clipShape(Capsule())
            }
            .frame(height: 8)
            HStack {
                Text("\(Int((s.spent / total * 100).rounded()))% of \(usd(s.monthlyBudget, fraction: 0))")
                Spacer()
                Text("reserve \(usd(s.reservedAmount, fraction: 0))")
            }
            .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    // MARK: Sparkline

    private struct Day: Identifiable {
        let date: Date
        let cost: Double
        var id: Date { date }
    }

    private func sparkline(_ s: BudgetStatus) -> some View {
        let cal = Calendar.current
        let start = BudgetStatus.monthStart(of: Date())
        let monthEnd = cal.date(byAdding: .day, value: s.daysInMonth, to: start)!
        let days = (0..<s.dayOfMonth).map { i -> Day in
            let d = cal.date(byAdding: .day, value: i, to: start)!
            return Day(date: d, cost: model.summary?.byDay[d] ?? 0)
        }
        let active = days.filter { $0.cost > 0 }
        let average = active.isEmpty ? 0 : active.reduce(0) { $0 + $1.cost } / Double(active.count)
        let prev = model.previousSummary
        let prevStart = cal.date(byAdding: .month, value: -1, to: start)!
        let prevDaily = (0..<s.daysInMonth).compactMap { i -> Day? in
            guard let p = prev, let pd = cal.date(byAdding: .day, value: i, to: prevStart),
                  pd < start else { return nil }
            return Day(date: cal.date(byAdding: .day, value: i, to: start)!, cost: p.byDay[pd] ?? 0)
        }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Daily spend").font(.caption.weight(.semibold))
                Spacer()
                Text("avg \(usd(average, fraction: 0)) · allowance \(usd(s.dailyAllowance, fraction: 0))")
                    .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
            Chart {
                ForEach(prevDaily) { d in
                    LineMark(x: .value("Day", d.date, unit: .day), y: .value("Spend", d.cost),
                             series: .value("Series", "last month"))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .interpolationMethod(.monotone)
                }
                ForEach(days) { d in
                    BarMark(x: .value("Day", d.date, unit: .day), y: .value("Spend", d.cost))
                        .foregroundStyle(d.cost > s.dailyAllowance ? Color.red : Color.green)
                        .opacity(cal.isDateInToday(d.date) ? 1 : 0.65)
                        .cornerRadius(2)
                }
                RuleMark(y: .value("Allowance", s.dailyAllowance))
                    .foregroundStyle(Color.secondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartXScale(domain: start...monthEnd)
            .chartYAxis(.hidden)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.day(), anchor: .top).font(.caption2)
                }
            }
            .frame(height: 64)
            if let text = monthComparison(s) {
                Text(text).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .card()
    }

    /// Spend before today vs the same stretch of last month (the grey line above).
    private func monthComparison(_ s: BudgetStatus) -> String? {
        guard let prev = model.previousSummary, prev.total > 0 else { return nil }
        let cal = Calendar.current
        let start = BudgetStatus.monthStart(of: Date())
        let prevStart = cal.date(byAdding: .month, value: -1, to: start)!
        let samePoint = (0..<s.completedDays).reduce(0.0) { acc, i in
            acc + (cal.date(byAdding: .day, value: i, to: prevStart).flatMap { prev.byDay[$0] } ?? 0)
        }
        let so = s.spent - (model.summary?.totalToday ?? 0)
        let tail = "last month \(usd(prev.total, fraction: 0)) total"
        guard samePoint > 0 else { return tail }
        let pct = Int(((so - samePoint) / samePoint * 100).rounded())
        return "\(pct >= 0 ? "+" : "−")\(abs(pct))% vs same point last month · " + tail
    }

    // MARK: Tiles

    private func tiles(_ s: BudgetStatus) -> some View {
        HStack(spacing: 8) {
            tile("Spent", usd(s.spent, fraction: 0))
            tile("Today", usd(model.summary?.totalToday ?? 0, fraction: 0))
            tile("Remaining", usd(s.remainingThisMonth, fraction: 0))
        }
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.system(.body, design: .rounded).weight(.semibold)).monospacedDigit()
        }
        .card()
    }

    // MARK: Breakdown

    private func breakdown(_ summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("", selection: $ui.breakdown) {
                ForEach(ViewState.Breakdown.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden()

            switch ui.breakdown {
            case .models: models(summary)
            case .projects: projects(summary)
            case .sessions: sessions(summary)
            }
        }
        .card()
    }

    private func models(_ summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(summary.models, id: \.name) { m in
                row(name: m.name.replacingOccurrences(of: "claude-", with: ""),
                    cost: m.usage.cost, share: summary.total > 0 ? m.usage.cost / summary.total : 0,
                    detail: "today \(usd(m.usage.costToday)) · \(m.usage.messages) msgs",
                    tokens: "in \(tokens(m.usage.inputTokens)) · out \(tokens(m.usage.outputTokens)) · "
                        + "cache w \(tokens(m.usage.cacheWriteTokens)) · r \(tokens(m.usage.cacheReadTokens))")
            }
        }
    }

    private static let projectLimit = 8

    private func projects(_ summary: UsageSummary) -> some View {
        let all = summary.projects
        let rest = all.dropFirst(Self.projectLimit).reduce(0) { $0 + $1.usage.cost }
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(all.prefix(Self.projectLimit), id: \.name) { p in
                row(name: p.name, cost: p.usage.cost,
                    share: summary.total > 0 ? p.usage.cost / summary.total : 0,
                    detail: "today \(usd(p.usage.costToday)) · \(p.usage.messages) msgs", tokens: nil)
            }
            if all.count > Self.projectLimit {
                Text("+\(all.count - Self.projectLimit) more · \(usd(rest))")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private static let sessionLimit = 8

    private func sessions(_ summary: UsageSummary) -> some View {
        let all = summary.sessions
        let top = all.first?.usage.cost ?? 0
        return VStack(alignment: .leading, spacing: 10) {
            ForEach(all.prefix(Self.sessionLimit), id: \.id) { x in
                let u = x.usage
                row(name: u.title ?? u.project, cost: u.cost, share: top > 0 ? u.cost / top : 0,
                    detail: (u.title == nil ? "" : "\(u.project) · ")
                        + "\(u.start.formatted(.dateTime.month(.abbreviated).day())) · "
                        + "\(duration(u.end.timeIntervalSince(u.start))) · \(u.messages) msgs",
                    tokens: nil, showShare: false)
            }
            if all.count > Self.sessionLimit {
                Text("\(all.count) sessions this month")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func duration(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    /// `share` fills the bar; `showShare` also prints it as a percentage of the total.
    private func row(name: String, cost: Double, share: Double, detail: String, tokens: String?,
                     showShare: Bool = true) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(name).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                Spacer()
                Text(usd(cost)).font(.callout).monospacedDigit()
            }
            GeometryReader { geo in
                Capsule().fill(Color.secondary.opacity(0.2))
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.accentColor).frame(width: geo.size.width * min(max(share, 0), 1))
                    }
            }
            .frame(height: 4)
            Text(showShare ? "\(Int((share * 100).rounded()))% · \(detail)" : detail)
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if let tokens {
                Text(tokens).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
    }

    private func tokens(_ n: Int) -> String {
        let d = Double(n)
        switch d {
        case 1e9...: return String(format: "%.1fB", d / 1e9)
        case 1e6...: return String(format: "%.1fM", d / 1e6)
        case 1e3...: return String(format: "%.1fK", d / 1e3)
        default: return "\(n)"
        }
    }

    // MARK: Settings & footer

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Monthly budget")
                Spacer()
                TextField("", value: $model.monthlyBudget, format: .currency(code: "USD"))
                    .frame(width: 110)
                    .multilineTextAlignment(.trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("Reserve: \(Int(model.reservePercent))%")
                Slider(value: $model.reservePercent, in: 0...90, step: 1)
            }
            Picker("Menu bar", selection: $model.menuBarMode) {
                ForEach(UsageModel.MenuBarMode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            Text("Source: Claude Code logs · pricing: \(model.pricingSource)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .card()
    }

    private var footer: some View {
        HStack {
            if let t = model.lastUpdated {
                Text("Updated \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Copy JSON") { model.copyExport(json: true) }
                Menu("Copy CSV") {
                    ForEach(Export.Grouping.allCases, id: \.self) { g in
                        Button("by \(g.rawValue)") { model.copyExport(json: false, by: g) }
                    }
                }
            } label: { Image(systemName: "square.and.arrow.up") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .help("Copy this month's usage to the clipboard")
                .disabled(model.summary == nil)
            Button { Task { await model.refresh() } } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless).help("Refresh").disabled(model.isLoading)
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
    }

    // MARK: Helpers

    private func color(_ s: BudgetStatus?) -> Color {
        guard let s else { return .secondary }
        if s.wholeDaysAhead < 0 { return .red }
        if s.wholeDaysAhead > 0 { return .green }
        return .primary
    }

    private func usd(_ v: Double, fraction: Int? = nil) -> String {
        if let fraction {
            return v.formatted(.currency(code: "USD").precision(.fractionLength(fraction)))
        }
        return v.formatted(.currency(code: "USD"))
    }
}
