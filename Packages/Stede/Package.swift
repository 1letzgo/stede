// swift-tools-version: 6.2
import PackageDescription

// Zwei Bibliotheken: StedeCore (Modelle, Parser, Clients, Stores, Daten — reines
// Foundation, testbar, ohne UI) und StedeUI (SwiftUI-Oberfläche). Die App im
// Xcode-Projekt ist nur noch die Hülle mit Icon, Info.plist und Entitlements.
let package = Package(
    name: "Stede",
    defaultLocalization: "de",
    platforms: [.iOS(.v26), .macOS(.v26), .visionOS(.v26)],
    products: [
        .library(name: "StedeCore", targets: ["StedeCore"]),
        .library(name: "StedeUI", targets: ["StedeUI"]),
    ],
    targets: [
        .target(
            name: "StedeCore",
            resources: [.process("Resources")],
            swiftSettings: [
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .target(
            name: "StedeUI",
            dependencies: ["StedeCore"],
            resources: [.process("Resources")],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("MemberImportVisibility"),
                .enableUpcomingFeature("InferIsolatedConformances"),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
            ]
        ),
        .testTarget(
            name: "StedeCoreTests",
            dependencies: ["StedeCore"],
            resources: [.copy("Fixtures")]
        ),
    ],
    swiftLanguageModes: [.v5]
)
