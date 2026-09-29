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
}

struct UsageView: View {
    @ObservedObject var model: UsageModel
    @StateObject private var ui = ViewState()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if let s = model.status {
                Divider()
                stats(s)
            }
            if let unpriced = model.summary?.unpricedModels, !unpriced.isEmpty {
                Text("No price for \(unpriced.sorted().joined(separator: ", ")); not counted.")
                    .font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            DisclosureGroup("Settings", isExpanded: $ui.showSettings) { settings }
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 300)
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

    private func stats(_ s: BudgetStatus) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
            row("Spent this month", usd(s.spent))
            row("Expected by today", usd(s.expectedSpend) + " (\(s.completedDays)/\(s.daysInMonth) days)")
            row("Daily allowance", usd(s.dailyAllowance))
            row("Left for today", usd(s.leftToday))
            row("Usable budget", usd(s.usableBudget))
            row("Remaining", usd(s.remainingThisMonth))
            row("Reserved", usd(s.reservedAmount) + " (\(Int(s.reservePercent))%)")
        }
        .font(.callout)
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
