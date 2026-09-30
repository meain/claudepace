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
    /// Raw date under the cursor on the sparkline; nil when not hovering.
    @Published var hoveredDate: Date?
    /// Breakdown rows disclosed to show their details, keyed by tab and row id.
    @Published var expanded: Set<String> = []

    init(breakdown: Breakdown = .models) { self.breakdown = breakdown }
}

final class HoverState: ObservableObject {
    @Published var on = false
}

/// An NSMenu-style item: full-width row with a rounded accent highlight on hover.
struct MenuRow<Content: View>: View {
    var shortcut: KeyEquivalent?
    var action: (() -> Void)?
    /// Receives whether the row is highlighted, so secondary text can switch to white.
    @ViewBuilder var content: (Bool) -> Content
    @StateObject private var hover = HoverState()

    init(shortcut: KeyEquivalent? = nil, action: (() -> Void)? = nil,
         @ViewBuilder content: @escaping (Bool) -> Content) {
        self.shortcut = shortcut
        self.action = action
        self.content = content
    }

    var body: some View {
        Group {
            if let action {
                Button(action: action) { row }
                    .buttonStyle(.plain)
                    .keyboardShortcut(shortcut.map { KeyboardShortcut($0) })
            } else {
                row
            }
        }
        .padding(.horizontal, 5)
    }

    private var row: some View {
        HStack(spacing: 8) { content(hover.on) }
            .padding(.horizontal, 9).padding(.vertical, 3)
            .frame(maxWidth: .infinity, minHeight: 22, alignment: .leading)
            .foregroundStyle(hover.on ? Color.white : Color.primary)
            .background(hover.on ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 5))
            .contentShape(Rectangle())
            .onHover { hover.on = $0 }
    }
}

/// A borderless toolbar icon with a subtle hover background.
struct ToolbarIcon: View {
    let symbol: String
    let help: String
    var shortcut: KeyEquivalent?
    let action: () -> Void
    @StateObject private var hover = HoverState()

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: 26, height: 22)
                .background(hover.on ? Color.primary.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .keyboardShortcut(shortcut.map { KeyboardShortcut($0) })
        .onHover { hover.on = $0 }
        .help(help)
    }
}

/// Secondary text colour inside a `MenuRow`.
private func dim(_ highlighted: Bool) -> Color { highlighted ? .white.opacity(0.8) : .secondary }

private struct Glyph: View {
    let name: String
    var body: some View {
        if name.isEmpty {
            Color.clear.frame(width: 16, height: 1)
        } else {
            Image(systemName: name).font(.system(size: 12)).frame(width: 16).opacity(0.85)
        }
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
        VStack(alignment: .leading, spacing: 0) {
            header
            if let s = model.status {
                hero(s)
                separator
                stats(s)
                if let unpriced = model.summary?.unpricedModels, !unpriced.isEmpty {
                    Text("No price for \(unpriced.sorted().joined(separator: ", ")); not counted.")
                        .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 14).padding(.vertical, 3)
                }
                separator
                sparkline(s)
            }
            if let summary = model.summary, !summary.byModel.isEmpty {
                separator
                breakdown(summary)
            }
            separator
            actions
        }
        .padding(.vertical, 5)
        .font(.system(size: 13))
        .frame(width: 340)
    }

    private var separator: some View {
        Divider().padding(.horizontal, 14).padding(.vertical, 5)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 3)
    }

    // MARK: Header & hero

    private var header: some View {
        HStack(spacing: 6) {
            Text("CLAUDE PACE · \(Date().formatted(.dateTime.month(.wide)).uppercased())")
            Spacer()
            if model.isLoading { ProgressView().controlSize(.mini) }
        }
        .font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
        .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 3)
    }

    private func hero(_ s: BudgetStatus) -> some View {
        let today = model.summary?.totalToday ?? 0
        let target = s.todayTarget(spentToday: today)
        let left = s.paceLeftToday(spentToday: today)
        return VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(usd(abs(left), fraction: 0))
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(left >= 0 ? Color.primary : Color.red)
                Text(left >= 0 ? "left today" : "over today's target").foregroundStyle(.secondary)
            }
            Text("\(usd(today, fraction: 0)) of \(usd(target, fraction: 0)) target · \(s.daysRemaining) days left")
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
            monthBar(s).padding(.top, 8)
        }
        .monospacedDigit()
        .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 8)
    }

    /// Spend vs full monthly budget; the orange tail is the reserve, the tick is where spend should be today.
    private func monthBar(_ s: BudgetStatus) -> some View {
        let total = max(s.monthlyBudget, 0.01)
        let spent = min(max(s.spent / total, 0), 1)
        let expected = min(max(s.expectedSpend / total, 0), 1)
        let reserve = min(max(s.reservedAmount / total, 0), 1)
        return VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(Color.primary.opacity(0.1))
                        Rectangle().fill(Color.orange.opacity(0.45))
                            .frame(width: w * reserve)
                            .offset(x: w * (1 - reserve))
                        Rectangle().fill(s.wholeDaysAhead < 0 ? Color.red : Color.accentColor)
                            .frame(width: w * spent)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    RoundedRectangle(cornerRadius: 1).fill(Color.primary)
                        .frame(width: 2, height: 12)
                        .offset(x: w * expected - 1)
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(Int((s.spent / total * 100).rounded()))% of \(usd(s.monthlyBudget, fraction: 0))")
                Spacer()
                Text("reserve \(usd(s.reservedAmount, fraction: 0))")
            }
            .font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    // MARK: Stats

    private func stats(_ s: BudgetStatus) -> some View {
        let ahead = s.daysAhead >= 0
        let pace = s.wholeDaysAhead < 0 ? Color.red : s.wholeDaysAhead > 0 ? Color.green : Color.primary
        return VStack(spacing: 0) {
            MenuRow { h in
                Glyph(name: ahead ? "checkmark" : "exclamationmark.triangle")
                    .foregroundStyle(h ? Color.white : pace)
                Text("Pace")
                Spacer()
                Text(String(format: "%.1f days %@", abs(s.daysAhead), ahead ? "ahead" : "behind"))
                    .fontWeight(.medium).foregroundStyle(h ? Color.white : pace)
            }
            statRow("sum", "Spent this month", s.spent)
            statRow("clock", "Today", model.summary?.totalToday ?? 0)
            statRow("circle.dashed", "Remaining", s.remainingThisMonth)
        }
        .monospacedDigit()
    }

    private func statRow(_ glyph: String, _ title: String, _ value: Double) -> some View {
        MenuRow { _ in
            Glyph(name: glyph)
            Text(title)
            Spacer()
            Text(usd(value)).fontWeight(.medium)
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
        let hovered = ui.hoveredDate.map { cal.startOfDay(for: $0) }
            .flatMap { d in d >= start && d < monthEnd ? d : nil }
        return VStack(alignment: .leading, spacing: 0) {
            sectionHeader("DAILY SPEND")
            VStack(alignment: .leading, spacing: 4) {
                Group {
                    if let h = hovered {
                        Text(hoverText(h, days: days, prevDaily: prevDaily))
                    } else {
                        Text("avg \(usd(average, fraction: 0)) · allowance \(usd(s.dailyAllowance, fraction: 0))")
                    }
                }
                .font(.system(size: 11.5)).foregroundStyle(.secondary)
                Chart {
                    ForEach(prevDaily) { d in
                        LineMark(x: .value("Day", d.date, unit: .day), y: .value("Spend", d.cost),
                                 series: .value("Series", "last month"))
                            .foregroundStyle(Color.secondary.opacity(0.55))
                            .lineStyle(StrokeStyle(lineWidth: 1))
                            .interpolationMethod(.monotone)
                    }
                    if let h = hovered {
                        RectangleMark(x: .value("Day", h, unit: .day))
                            .foregroundStyle(Color.primary.opacity(0.08))
                    }
                    ForEach(days) { d in
                        BarMark(x: .value("Day", d.date, unit: .day), y: .value("Spend", d.cost))
                            .foregroundStyle(d.cost > s.dailyAllowance ? Color.red : Color.accentColor)
                            .opacity(d.date == hovered || (hovered == nil && cal.isDateInToday(d.date)) ? 1 : 0.7)
                            .cornerRadius(1.5)
                    }
                    RuleMark(y: .value("Allowance", s.dailyAllowance))
                        .foregroundStyle(Color.secondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
                .chartXScale(domain: start...monthEnd)
                .chartXSelection(value: $ui.hoveredDate)
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 44)
                if let text = monthComparison(s) {
                    Text(text).font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .padding(.horizontal, 14).padding(.top, 2).padding(.bottom, 2)
        }
    }

    /// Label for the hovered sparkline day: its spend, plus last month's same day when known.
    private func hoverText(_ day: Date, days: [Day], prevDaily: [Day]) -> String {
        let label = day.formatted(.dateTime.month(.abbreviated).day())
        let cost = days.first { $0.date == day }.map { usd($0.cost, fraction: 0) }
        let prev = prevDaily.first { $0.date == day }.map { "last month \(usd($0.cost, fraction: 0))" }
        return ([label] + [cost, prev].compactMap { $0 }).joined(separator: " · ")
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

    // MARK: Breakdown

    private func breakdown(_ summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("BREAKDOWN")
            Picker("", selection: $ui.breakdown) {
                ForEach(ViewState.Breakdown.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().controlSize(.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 6)

            switch ui.breakdown {
            case .models: models(summary)
            case .projects: projects(summary)
            case .sessions: sessions(summary)
            }
        }
        .monospacedDigit()
    }

    private func models(_ summary: UsageSummary) -> some View {
        VStack(spacing: 0) {
            ForEach(summary.models, id: \.name) { m in
                row(id: "m:\(m.name)", name: m.name.replacingOccurrences(of: "claude-", with: ""),
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
        return VStack(spacing: 0) {
            ForEach(all.prefix(Self.projectLimit), id: \.name) { p in
                row(id: "p:\(p.name)", name: p.name, cost: p.usage.cost,
                    share: summary.total > 0 ? p.usage.cost / summary.total : 0,
                    detail: "today \(usd(p.usage.costToday)) · \(p.usage.messages) msgs", tokens: nil)
            }
            if all.count > Self.projectLimit {
                moreRow("+\(all.count - Self.projectLimit) more", value: usd(rest))
            }
        }
    }

    private static let sessionLimit = 8

    private func sessions(_ summary: UsageSummary) -> some View {
        let all = summary.sessions
        let top = all.first?.usage.cost ?? 0
        return VStack(spacing: 0) {
            ForEach(all.prefix(Self.sessionLimit), id: \.id) { x in
                let u = x.usage
                row(id: "s:\(x.id)", name: u.title ?? u.project, cost: u.cost, share: top > 0 ? u.cost / top : 0,
                    detail: (u.title == nil ? "" : "\(u.project) · ")
                        + "\(u.start.formatted(.dateTime.month(.abbreviated).day())) · "
                        + "\(duration(u.end.timeIntervalSince(u.start))) · \(u.messages) msgs",
                    tokens: nil, showShare: false)
            }
            if all.count > Self.sessionLimit {
                moreRow("\(all.count) sessions this month", value: nil)
            }
        }
    }

    private func moreRow(_ title: String, value: String?) -> some View {
        MenuRow { h in
            Color.clear.frame(width: 10, height: 1) // lines up with the disclosure chevron
            Text(title).foregroundStyle(dim(h))
            Spacer()
            if let value { Text(value).foregroundStyle(dim(h)) }
        }
    }

    private func duration(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        return m >= 60 ? "\(m / 60)h \(m % 60)m" : "\(m)m"
    }

    /// A disclosure row; clicking it reveals the share bar, `detail` and `tokens`.
    /// `showShare` prints `share` as a percentage of the total next to the cost.
    private func row(id: String, name: String, cost: Double, share: Double, detail: String, tokens: String?,
                     showShare: Bool = true) -> some View {
        let open = ui.expanded.contains(id)
        return VStack(alignment: .leading, spacing: 0) {
            MenuRow(action: {
                if open { ui.expanded.remove(id) } else { ui.expanded.insert(id) }
            }) { h in
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold)).foregroundStyle(dim(h))
                    .rotationEffect(.degrees(open ? 90 : 0))
                    .frame(width: 10)
                Text(name).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 8)
                if showShare {
                    Text("\(Int((share * 100).rounded()))%").font(.system(size: 11)).foregroundStyle(dim(h))
                        .frame(width: 30, alignment: .trailing)
                }
                // Fixed column so the share percentages line up across rows.
                Text(usd(cost)).fontWeight(.medium).frame(minWidth: 72, alignment: .trailing)
            }
            if open {
                VStack(alignment: .leading, spacing: 3) {
                    GeometryReader { geo in
                        Capsule().fill(Color.primary.opacity(0.08))
                            .overlay(alignment: .leading) {
                                Capsule().fill(Color.accentColor)
                                    .frame(width: geo.size.width * min(max(share, 0), 1))
                            }
                    }
                    .frame(height: 3)
                    Text(detail)
                    if let tokens { Text(tokens) }
                }
                .fixedSize(horizontal: false, vertical: true)
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .padding(.leading, 33).padding(.trailing, 14).padding(.top, 2).padding(.bottom, 4)
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

    // MARK: Actions, settings & footer

    /// Settings panel (when open) above a single toolbar line: last update, then icon actions.
    private var actions: some View {
        VStack(alignment: .leading, spacing: 0) {
            if ui.showSettings { settings }
            HStack(spacing: 2) {
                if let t = model.lastUpdated {
                    TimelineView(.periodic(from: .now, by: 30)) { ctx in
                        Text("Updated \(ago(t, now: ctx.date))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                ToolbarIcon(symbol: ui.showSettings ? "gearshape.fill" : "gearshape", help: "Settings (⌘,)",
                            shortcut: ",") { ui.showSettings.toggle() }
                ToolbarIcon(symbol: "arrow.clockwise", help: "Refresh (⌘R)", shortcut: "r") {
                    Task { await model.refresh() }
                }
                .disabled(model.isLoading)
                Menu {
                    Button("Copy JSON") { model.copyExport(json: true) }
                    Menu("Copy CSV") {
                        ForEach(Export.Grouping.allCases, id: \.self) { g in
                            Button("by \(g.rawValue)") { model.copyExport(json: false, by: g) }
                        }
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .frame(width: 26, height: 22)
                .help("Copy this month's usage to the clipboard")
                .disabled(model.summary == nil)
                ToolbarIcon(symbol: "power", help: "Quit Claude Pace (⌘Q)", shortcut: "q") {
                    NSApplication.shared.terminate(nil)
                }
            }
            .padding(.leading, 14).padding(.trailing, 9).padding(.vertical, 2)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Monthly budget")
                Spacer()
                TextField("", value: $model.monthlyBudget, format: .currency(code: "USD"))
                    .frame(width: 100)
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
                .font(.system(size: 10.5)).foregroundStyle(.secondary)
        }
        .font(.system(size: 12.5)).controlSize(.small)
        .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 8)
    }


    // MARK: Helpers

    private func ago(_ t: Date, now: Date) -> String {
        let secs = now.timeIntervalSince(t)
        if secs < 60 { return "just now" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: t, relativeTo: now)
    }

    private func usd(_ v: Double, fraction: Int? = nil) -> String {
        if let fraction {
            return v.formatted(.currency(code: "USD").precision(.fractionLength(fraction)))
        }
        return v.formatted(.currency(code: "USD"))
    }
}
