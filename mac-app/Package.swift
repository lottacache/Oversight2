// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OversightIsland",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "OversightIsland", targets: ["OversightIsland"])],
    targets: [.executableTarget(name: "OversightIsland", path: "Sources/OversightIsland")]
)
