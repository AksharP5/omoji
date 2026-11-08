// swift-tools-version:5.10
import PackageDescription

let package = Package(
  name: "omoji",
  platforms: [.macOS(.v13)],
  targets: [
    .target(name: "OmojiCore"),
    .executableTarget(name: "omoji", dependencies: ["OmojiCore"]),
    .testTarget(name: "OmojiCoreTests", dependencies: ["OmojiCore"])
  ]
)
