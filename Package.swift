// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PAIAIME", platforms: [.macOS(.v13)], products: [
    .executable(name: "PAIANativeLab", targets: ["NativeIME"]),
    .executable(name: "paia-benchmark", targets: ["BenchmarkCLI"]),
    .executable(name: "paia-constraints", targets: ["ConstraintCLI"])
], targets: [
    .target(name: "CRimeShim", publicHeadersPath: "include", linkerSettings: [.linkedLibrary("dl"), .linkedLibrary("pthread")]),
    .target(name: "TextBoundary"),
    .target(name: "LexiconCore"),
    .target(name: "SettingsCore"),
    .target(name: "SessionCore", dependencies: ["TextBoundary"]),
    .target(name: "ConstraintCore", dependencies: ["SessionCore", "TextBoundary"]),
    .target(name: "EngineBridge", dependencies: ["CRimeShim", "SessionCore", "TextBoundary", "ConstraintCore", "LexiconCore", "SettingsCore"]),
    .target(name: "NativeHost", dependencies: ["EngineBridge", "SessionCore", "TextBoundary", "ConstraintCore", "LexiconCore", "SettingsCore"]),
    .executableTarget(name: "NativeIME", dependencies: ["NativeHost", "EngineBridge", "SettingsCore"]),
    .executableTarget(name: "BenchmarkCLI", dependencies: ["EngineBridge", "SessionCore"]),
    .executableTarget(name: "ConstraintCLI", dependencies: ["EngineBridge", "SessionCore", "ConstraintCore"]),
    .testTarget(name: "NativeControlTests", dependencies: ["NativeHost", "EngineBridge", "SessionCore", "ConstraintCore"]),
    .testTarget(name: "LexiconCoreTests", dependencies: ["LexiconCore"]),
    .testTarget(name: "SettingsCoreTests", dependencies: ["SettingsCore"]),
    .testTarget(name: "SettingsNativeTests", dependencies: ["SettingsCore", "NativeHost", "EngineBridge", "LexiconCore"]),
    .testTarget(name: "PersonalControlTests", dependencies: ["NativeHost", "LexiconCore"]),
    .testTarget(name: "PersonalEngineTests", dependencies: ["LexiconCore", "EngineBridge", "NativeHost"]),
    .testTarget(name: "ConstraintCoreTests", dependencies: ["ConstraintCore", "SessionCore"]),
    .testTarget(name: "ConstraintHostTests", dependencies: ["ConstraintCore", "EngineBridge", "NativeHost"]),
    .testTarget(name: "SessionCoreTests", dependencies: ["SessionCore", "TextBoundary"]),
    .testTarget(name: "EngineTests", dependencies: ["EngineBridge", "SessionCore"]),
    .testTarget(name: "AppKitHostTests", dependencies: ["NativeHost", "EngineBridge", "SessionCore"])
])
