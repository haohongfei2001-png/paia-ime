// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "PAIAIME", platforms: [.macOS(.v13)], products: [
    .executable(name: "PAIANativeLab", targets: ["NativeIME"]),
    .executable(name: "paia-benchmark", targets: ["BenchmarkCLI"])
], targets: [
    .target(name: "CRimeShim", publicHeadersPath: "include", linkerSettings: [.linkedLibrary("dl"), .linkedLibrary("pthread")]),
    .target(name: "TextBoundary"),
    .target(name: "SessionCore", dependencies: ["TextBoundary"]),
    .target(name: "EngineBridge", dependencies: ["CRimeShim", "SessionCore", "TextBoundary"]),
    .target(name: "NativeHost", dependencies: ["EngineBridge", "SessionCore", "TextBoundary"]),
    .executableTarget(name: "NativeIME", dependencies: ["NativeHost", "EngineBridge"]),
    .executableTarget(name: "BenchmarkCLI", dependencies: ["EngineBridge", "SessionCore"]),
    .testTarget(name: "SessionCoreTests", dependencies: ["SessionCore", "TextBoundary"]),
    .testTarget(name: "EngineTests", dependencies: ["EngineBridge", "SessionCore"]),
    .testTarget(name: "AppKitHostTests", dependencies: ["NativeHost", "EngineBridge", "SessionCore"])
])
