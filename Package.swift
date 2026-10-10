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
            dependencies: modules.map { .target(name: $0) },
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
