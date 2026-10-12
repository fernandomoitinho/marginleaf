// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Marginleaf",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Marginleaf", targets: ["Marginleaf"]),
    ],
    dependencies: [
        // GitHub's cmark fork (tables, task lists, strikethrough, autolinks, footnotes).
        .package(url: "https://github.com/swiftlang/swift-cmark.git", branch: "gfm"),
    ],
    targets: [
        // Pure logic, no AppKit: unit-tested in CI.
        .target(
            name: "MarginleafCore",
            dependencies: [
                .product(name: "cmark-gfm", package: "swift-cmark"),
                .product(name: "cmark-gfm-extensions", package: "swift-cmark"),
            ]
        ),
        // The app itself (AppKit + WebKit).
        .executableTarget(
            name: "Marginleaf",
            dependencies: ["MarginleafCore"]
        ),
        .testTarget(
            name: "MarginleafCoreTests",
            dependencies: ["MarginleafCore"]
        ),
    ]
)
