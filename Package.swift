// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacSnap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacSnap", targets: ["MacSnap"]),
        .executable(name: "MacSnapUninstaller", targets: ["MacSnapUninstaller"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "MacSnap",
            dependencies: [.product(name: "Sparkle", package: "Sparkle"), "MacSnapUninstallation"],
            path: "Sources/MacSnap",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .target(name: "MacSnapUninstallation"),
        .executableTarget(name: "MacSnapUninstaller", dependencies: ["MacSnapUninstallation"]),
        .testTarget(
            name: "MacSnapTests",
            dependencies: ["MacSnap", "MacSnapUninstallation"],
            path: "Tests/MacSnapTests"
        ),
    ]
)
