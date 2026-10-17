// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LangSwapper",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure, platform-free detection logic: layout maps, dictionaries, scoring.
        .target(name: "LangSwapperCore"),
        // Menu-bar app: event tap, input sources (TIS/UCKeyTranslate), text rewriting.
        .executableTarget(
            name: "LangSwapper",
            dependencies: ["LangSwapperCore"],
            linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("AppKit")]
        ),
    ]
)
