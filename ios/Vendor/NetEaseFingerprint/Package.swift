// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "NetEaseFingerprint",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "NativeFingerprint", targets: ["NativeFingerprint"])],
    targets: [.target(name: "NativeFingerprint", path: "Native", publicHeadersPath: "include",
        cSettings: [
            .headerSearchPath("runtime"),
            .define("WASM_RT_USE_MMAP", to: "0"),
            .define("WASM_RT_MEMCHECK_BOUNDS_CHECK", to: "1"),
            .unsafeFlags(["-fno-optimize-sibling-calls", "-frounding-math", "-ffp-contract=off"])
        ]),
        .testTarget(name: "NativeFingerprintTests", dependencies: ["NativeFingerprint"], path: "Tests")],
    cLanguageStandard: .c11
)
