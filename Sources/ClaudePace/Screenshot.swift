import AppKit
import SwiftUI

/// `ClaudePace --screenshot out.png [--tab models|projects|sessions]` renders the popup to a PNG and
/// exits. It draws the view itself, so unlike `screencapture` it needs no Screen Recording permission.
@MainActor
enum Screenshot {
    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--screenshot"), args.indices.contains(i + 1) else { return }
        let path = args[i + 1]
        let tab = args.firstIndex(of: "--tab").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
            .flatMap { t in ViewState.Breakdown.allCases.first { $0.rawValue.lowercased() == t } } ?? .models

        Task { @MainActor in
            NSApplication.shared.setActivationPolicy(.accessory)
            let model = UsageModel()
            // The model's own refresh loop is already running; wait for both scans to land.
            for _ in 0..<600 where model.summary == nil || model.previousSummary == nil {
                try? await Task.sleep(for: .milliseconds(100))
            }
            let root = UsageView(model: model, breakdown: tab)
                .background(Color(nsColor: .windowBackgroundColor))
            let host = NSHostingView(rootView: root)
            let window = NSWindow(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                                  styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            window.setContentSize(host.fittingSize)
            window.orderFrontRegardless()
            try? await Task.sleep(for: .seconds(1)) // let Charts finish laying out
            host.layoutSubtreeIfNeeded()

            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { exit(1) }
            host.cacheDisplay(in: host.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]),
                  (try? png.write(to: URL(fileURLWithPath: path))) != nil else { exit(1) }
            print("Wrote \(path)")
            exit(0)
        }
    }
}
