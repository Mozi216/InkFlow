// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "InkFlowCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "InkFlowCore", targets: ["InkFlowCore"])],
    targets: [
        .target(name: "InkFlowCore"),
        .testTarget(name: "InkFlowCoreTests", dependencies: ["InkFlowCore"],
                    resources: [.copy("Fixtures")])
    ]
)
