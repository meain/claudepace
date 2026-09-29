import BudgetCore
import SwiftUI

@main
struct ClaudePaceApp: App {
    @StateObject private var model = UsageModel()

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
    @Published var showSettings = false
    @Published var showModels = true
}

struct UsageView: View {
    @ObservedObject var model: UsageModel
    @StateObject private var ui = ViewState()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let s = model.status {
                progressBar(s)
                Divider()
                stats(s)
            }
            if let unpriced = model.summary?.unpricedModels, !unpriced.isEmpty {
                Text("No price for \(unpriced.sorted().joined(separator: ", ")); not counted.")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            if let summary = model.summary, !summary.byModel.isEmpty {
                Divider()
                DisclosureGroup("By model", isExpanded: $ui.showModels) { models(summary) }
            }
            Divider()
            DisclosureGroup("Settings", isExpanded: $ui.showSettings) { settings }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 320)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(model.status?.label ?? "—")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundStyle(color(model.status))
            if let s = model.status {
                Text(String(format: "%+.1f days", s.daysAhead)).foregroundStyle(.secondary)
            }
            Spacer()
            if model.isLoading { ProgressView().controlSize(.small) }
        }
    }

    /// Spend vs full monthly budget; the orange tail is the reserve and the tick marks where spend should be today.
    private func progressBar(_ s: BudgetStatus) -> some View {
        let total = max(s.monthlyBudget, 0.01)
        let spent = min(max(s.spent / total, 0), 1)
        let expected = min(max(s.expectedSpend / total, 0), 1)
        let reserve = min(max(s.reservedAmount / total, 0), 1)
        return VStack(alignment: .leading, spacing: 3) {
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
            Text("\(Int((s.spent / total * 100).rounded()))% of \(usd(s.monthlyBudget)) · reserve \(usd(s.reservedAmount)) · tick = expected today")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func stats(_ s: BudgetStatus) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            row("Spent this month", usd(s.spent))
            row("Spent today", usd(model.summary?.totalToday ?? 0))
            row("Expected by today", usd(s.expectedSpend) + " (\(s.completedDays)/\(s.daysInMonth) days)")
            row("Daily allowance", usd(s.dailyAllowance))
            row("Left for today", usd(s.leftToday))
            row("Usable budget", usd(s.usableBudget))
            row("Remaining", usd(s.remainingThisMonth))
            row("Reserved", usd(s.reservedAmount) + " (\(Int(s.reservePercent))%)")
        }
        .font(.callout)
    }

    private func models(_ summary: UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(summary.models, id: \.name) { m in
                let share = summary.total > 0 ? m.usage.cost / summary.total : 0
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(m.name.replacingOccurrences(of: "claude-", with: ""))
                            .font(.callout.weight(.medium))
                        Spacer()
                        Text(usd(m.usage.cost)).font(.callout).monospacedDigit()
                    }
                    ProgressView(value: share)
                    Text("\(Int((share * 100).rounded()))% · today \(usd(m.usage.costToday)) · \(m.usage.messages) msgs")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    Text("in \(tokens(m.usage.inputTokens)) · out \(tokens(m.usage.outputTokens)) · "
                         + "cache w \(tokens(m.usage.cacheWriteTokens)) · r \(tokens(m.usage.cacheReadTokens))")
                        .font(.caption2).foregroundStyle(.secondary).monospacedDigit()
                }
            }
        }
        .padding(.top, 6)
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

    private func row(_ k: String, _ v: String) -> some View {
        GridRow {
            Text(k).foregroundStyle(.secondary)
            Text(v).monospacedDigit()
        }
    }

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
            Text("Source: Claude Code logs · pricing: \(model.pricingSource)")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, 6)
    }

    private var footer: some View {
        HStack {
            if let t = model.lastUpdated {
                Text("Updated \(t.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Refresh") { Task { await model.refresh() } }
                .disabled(model.isLoading)
            Button("Quit") { NSApplication.shared.terminate(nil) }
        }
    }

    private func color(_ s: BudgetStatus?) -> Color {
        guard let s else { return .secondary }
        if s.wholeDaysAhead < 0 { return .red }
        if s.wholeDaysAhead > 0 { return .green }
        return .primary
    }

    private func usd(_ v: Double) -> String {
        v.formatted(.currency(code: "USD"))
    }
}
