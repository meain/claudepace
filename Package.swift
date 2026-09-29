// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClaudePace",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "BudgetCore"),
        .executableTarget(name: "ClaudePace", dependencies: ["BudgetCore"]),
        .executableTarget(name: "BudgetChecks", dependencies: ["BudgetCore"]),
    ]
)
