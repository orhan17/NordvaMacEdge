// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NordvaMacEdge",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CMultitouch"),
        .target(name: "NordvaMacEdgeCore"),
        .executableTarget(name: "NordvaMacEdge", dependencies: ["CMultitouch", "NordvaMacEdgeCore"]),
        .testTarget(name: "NordvaMacEdgeCoreTests", dependencies: ["NordvaMacEdgeCore"]),
    ]
)
