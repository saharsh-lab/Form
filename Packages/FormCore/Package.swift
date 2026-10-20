// swift-tools-version:5.9
import PackageDescription

/// FormCore holds Form's pure, platform-independent logic: unit conversion,
/// nutrition scaling and totals, target progress, workout volume, personal
/// records, timers and input validation. It depends only on Foundation so it
/// can be unit-tested with `swift test` on macOS or Linux.
let package = Package(
    name: "FormCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FormCore", targets: ["FormCore"])
    ],
    targets: [
        .target(name: "FormCore"),
        .testTarget(name: "FormCoreTests", dependencies: ["FormCore"])
    ]
)
