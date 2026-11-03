// swift-tools-version:6.0
import PackageDescription

let modules = ["DesignSystem", "Settings", "Annotation", "Selection", "Recording"]
/// Module-to-module dependencies; every other module stands alone.
let moduleDependencies: [String: [String]] = ["Recording": ["Selection"]]

let package = Package(
    name: "Recorder",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "Recorder", targets: ["Recorder"])
    ],
    dependencies: [
        // In-app updates. Scripts/build-app.sh embeds Sparkle.framework into the app bundle.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: modules.flatMap { name -> [Target] in
        [
            .target(
                name: name,
                dependencies: (moduleDependencies[name] ?? []).map { .target(name: $0) },
                swiftSettings: [.swiftLanguageMode(.v5)]
            ),
            .testTarget(
                name: "\(name)Tests",
                dependencies: [.target(name: name)],
                swiftSettings: [.swiftLanguageMode(.v5)]
            ),
        ]
    } + [
        .executableTarget(
            name: "Recorder",
            dependencies: modules.map { .target(name: $0) } + [.product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
