// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacSnap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacSnap", targets: ["MacSnap"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "MacSnap",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/MacSnap",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(
            name: "MacSnapTests",
            dependencies: ["MacSnap"],
            path: "Tests/MacSnapTests"
        ),
    ]
)
