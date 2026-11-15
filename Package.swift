// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MouseHerdr",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "MouseHerdr",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/MouseHerdr",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "MouseHerdrTests", dependencies: ["MouseHerdr"])
    ],
    swiftLanguageVersions: [.v5]
)
