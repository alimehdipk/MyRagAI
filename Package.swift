// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MyRagAI",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MyRagAI", targets: ["MyRagAI"])],
    targets: [
        .target(name: "RagCore"),
        .executableTarget(name: "MyRagAI", dependencies: ["RagCore"], resources: [.copy("Resources/AppIcon.png")]),
        .executableTarget(name: "RagCoreChecks", dependencies: ["RagCore"], path: "Tests/RagCoreChecks")
    ]
)
