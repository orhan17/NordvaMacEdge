// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "NordvaMacEdge",
    platforms: [.macOS(.v13)],
    targets: [
        // Только заголовок со структурой касания: раскладку в памяти гарантирует C.
        .target(name: "CMultitouch"),
        // Чистая логика жестов, без AppKit и железа, поэтому её можно тестировать.
        .target(name: "NordvaMacEdgeCore"),
        .executableTarget(name: "NordvaMacEdge", dependencies: ["CMultitouch", "NordvaMacEdgeCore"]),
        .testTarget(name: "NordvaMacEdgeCoreTests", dependencies: ["NordvaMacEdgeCore"]),
    ]
)
